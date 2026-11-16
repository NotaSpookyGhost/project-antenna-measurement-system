"""
nanovna_v2.py — Low-level driver for NanoVNA V2 / SAA-2N.

This module handles all binary protocol communication with the SAA-2N
via USB CDC serial port. It is the ONLY module that knows about opcodes,
register addresses, FIFO layout and byte packing.

Protocol reference: NanoRFE UG1101 (NanoVNA V2 User Manual)
Hardware: SAA-2N, DiSlord v1.4.02 FPU
Wire protocol: binary register/FIFO, little-endian, host-initiated

IMPORTANT: valuesFIFO returns RAW data — NO on-device user calibration
is applied. PC-side calibration must be handled separately if needed.
"""

import struct
import time
from dataclasses import dataclass, field
from typing import Optional

import serial


# ─── Protocol constants (VERIFIED from NanoRFE UG1101) ───────────────────

CMD_NOP       = 0x00
CMD_INDICATE  = 0x0D
CMD_READ      = 0x10
CMD_READ2     = 0x11
CMD_READ4     = 0x12
CMD_READFIFO  = 0x18
CMD_WRITE     = 0x20
CMD_WRITE2    = 0x21
CMD_WRITE4    = 0x22
CMD_WRITE8    = 0x23
CMD_WRITEFIFO = 0x28

REG_SWEEP_START    = 0x00   # uint64
REG_SWEEP_STEP     = 0x10   # uint64
REG_SWEEP_POINTS   = 0x20   # uint16
REG_VALUES_PER_F   = 0x22   # uint16
REG_VALUES_FIFO    = 0x30   # FIFO
REG_DEVICE_VARIANT = 0xF0   # uint8  V2 = 0x02
REG_PROTOCOL_VER   = 0xF1   # uint8  V2 wire = 0x01
REG_HW_REVISION    = 0xF2   # uint8
REG_FW_MAJOR       = 0xF3   # uint8
REG_FW_MINOR       = 0xF4   # uint8

FIFO_RECORD_SIZE = 32


# ─── Data classes ────────────────────────────────────────────────────────

@dataclass
class DeviceIdentity:
    """Identity information read from device registers."""
    device_variant: int = 0
    protocol_version: int = 0
    hardware_revision: int = 0
    firmware_major: int = 0
    firmware_minor: int = 0
    port: str = ""

    @property
    def is_v2(self) -> bool:
        return self.device_variant == 0x02

    def __str__(self) -> str:
        return (
            f"DeviceIdentity(variant=0x{self.device_variant:02X}, "
            f"protocol=0x{self.protocol_version:02X}, "
            f"hw_rev={self.hardware_revision}, "
            f"fw={self.firmware_major}.{self.firmware_minor}, "
            f"port={self.port})"
        )


@dataclass
class FIFORecord:
    """A single 32-byte FIFO record parsed from valuesFIFO."""
    fwd0_re: int = 0
    fwd0_im: int = 0
    rev0_re: int = 0
    rev0_im: int = 0
    rev1_re: int = 0
    rev1_im: int = 0
    freq_index: int = 0

    @property
    def fwd0(self) -> complex:
        return complex(self.fwd0_re, self.fwd0_im)

    @property
    def rev0(self) -> complex:
        return complex(self.rev0_re, self.rev0_im)

    @property
    def rev1(self) -> complex:
        return complex(self.rev1_re, self.rev1_im)

    @property
    def s11(self) -> complex:
        """S11 = REV0 / FWD0 (VERIFIED UG1101)"""
        if abs(self.fwd0) == 0:
            return complex(0, 0)
        return self.rev0 / self.fwd0

    @property
    def s21(self) -> complex:
        """S21 = REV1 / FWD0 (VERIFIED UG1101)"""
        if abs(self.fwd0) == 0:
            return complex(0, 0)
        return self.rev1 / self.fwd0


@dataclass
class SweepResult:
    """Result of a complete sweep acquisition."""
    start_hz: int = 0
    step_hz: int = 0
    points: int = 0
    records: list = field(default_factory=list)  # list[FIFORecord]

    @property
    def frequency_hz(self) -> list[float]:
        """Frequency array derived from sweep config and freq_index."""
        return [self.start_hz + r.freq_index * self.step_hz for r in self.records]

    @property
    def s11_complex(self) -> list[complex]:
        return [r.s11 for r in self.records]

    @property
    def s21_complex(self) -> list[complex]:
        return [r.s21 for r in self.records]

    @property
    def complete(self) -> bool:
        return (self.points > 0
                and len(self.records) == self.points
                and {record.freq_index for record in self.records} == set(range(self.points)))

    def to_dict(self) -> dict:
        """Convert to dict suitable for MATLAB bridge / JSON export."""
        return {
            "frequency_hz": self.frequency_hz,
            "s11_real": [s.real for s in self.s11_complex],
            "s11_imag": [s.imag for s in self.s11_complex],
            "s21_real": [s.real for s in self.s21_complex],
            "s21_imag": [s.imag for s in self.s21_complex],
            "start_hz": self.start_hz,
            "step_hz": self.step_hz,
            "points": self.points,
            "records_received": len(self.records),
        }


# ─── Exceptions ──────────────────────────────────────────────────────────

class NanoVNAError(Exception):
    """Base exception for NanoVNA V2 errors."""
    pass

class HandshakeError(NanoVNAError):
    """INDICATE handshake failed."""
    pass

class TimeoutError(NanoVNAError):
    """Read/write timeout."""
    pass

class FIFOError(NanoVNAError):
    """FIFO read returned unexpected data."""
    pass


# ─── Driver class ────────────────────────────────────────────────────────

class NanoVNA_V2:
    """Low-level driver for NanoVNA V2 / SAA-2N.

    Usage:
        vna = NanoVNA_V2()
        vna.connect("COM6")
        identity = vna.identify()
        result = vna.acquire_sweep(2_395_000_000, 2_405_000_000, 11)
        vna.disconnect()
    """

    def __init__(self):
        self._ser: Optional[serial.Serial] = None
        self._port: str = ""
        self._identity: Optional[DeviceIdentity] = None
        # Current sweep config (for freq calculation)
        self._sweep_start: int = 0
        self._sweep_step: int = 0
        self._sweep_points: int = 0

    # ── Connection ───────────────────────────────────────────────────

    @property
    def connected(self) -> bool:
        return self._ser is not None and self._ser.is_open

    def connect(self, port: str, timeout: float = 2.0) -> None:
        """Open serial connection to SAA-2N."""
        if self.connected:
            self.disconnect()
        self._ser = serial.Serial(
            port=port,
            baudrate=115200,
            timeout=timeout,
            write_timeout=timeout,
        )
        self._port = port
        time.sleep(0.3)  # let device settle

    def disconnect(self) -> None:
        """Close serial connection."""
        if self._ser and self._ser.is_open:
            try:
                self._ser.close()
            except Exception:
                pass
        self._ser = None
        self._port = ""
        self._identity = None

    def _ensure_connected(self) -> None:
        if not self.connected:
            raise NanoVNAError("Not connected. Call connect(port) first.")

    # ── Low-level register I/O ───────────────────────────────────────

    def _read1(self, addr: int) -> int:
        self._ser.write(bytes([CMD_READ, addr]))
        data = self._ser.read(1)
        if len(data) != 1:
            raise TimeoutError(f"Timeout reading 1 byte from 0x{addr:02X}")
        return data[0]

    def _read2(self, addr: int) -> int:
        self._ser.write(bytes([CMD_READ2, addr]))
        data = self._ser.read(2)
        if len(data) != 2:
            raise TimeoutError(f"Timeout reading 2 bytes from 0x{addr:02X}")
        return struct.unpack("<H", data)[0]

    def _read4(self, addr: int) -> int:
        self._ser.write(bytes([CMD_READ4, addr]))
        data = self._ser.read(4)
        if len(data) != 4:
            raise TimeoutError(f"Timeout reading 4 bytes from 0x{addr:02X}")
        return struct.unpack("<I", data)[0]

    def _write1(self, addr: int, val: int) -> None:
        self._ser.write(bytes([CMD_WRITE, addr, val & 0xFF]))

    def _write2(self, addr: int, val: int) -> None:
        self._ser.write(bytes([CMD_WRITE2, addr]) + struct.pack("<H", val))

    def _write8(self, addr: int, val: int) -> None:
        self._ser.write(bytes([CMD_WRITE8, addr]) + struct.pack("<Q", val))

    # ── INDICATE handshake ───────────────────────────────────────────

    def indicate(self) -> bool:
        """Send INDICATE (0x0D), expect '2' (0x32).
        Returns True if handshake succeeds.
        """
        self._ensure_connected()
        self._ser.reset_input_buffer()
        self._ser.write(bytes([CMD_INDICATE]))
        resp = self._ser.read(1)
        return len(resp) == 1 and resp[0] == 0x32

    # ── Identity ─────────────────────────────────────────────────────

    def identify(self) -> DeviceIdentity:
        """Read identity registers 0xF0..0xF4.
        Also verifies handshake.
        """
        self._ensure_connected()

        if not self.indicate():
            raise HandshakeError("INDICATE failed — device did not respond 0x32")

        identity = DeviceIdentity(
            device_variant=self._read1(REG_DEVICE_VARIANT),
            protocol_version=self._read1(REG_PROTOCOL_VER),
            hardware_revision=self._read1(REG_HW_REVISION),
            firmware_major=self._read1(REG_FW_MAJOR),
            firmware_minor=self._read1(REG_FW_MINOR),
            port=self._port,
        )
        self._identity = identity
        return identity

    # ── FIFO management ──────────────────────────────────────────────

    def clear_fifo(self) -> None:
        """Clear stale FIFO data per UG1101: write any value to 0x30."""
        self._ensure_connected()
        self._write1(REG_VALUES_FIFO, 0x00)
        time.sleep(0.1)
        self._ser.reset_input_buffer()

    def _read_fifo(self, num_records: int, timeout_s: float = 10.0) -> list[FIFORecord]:
        """Read num_records × 32-byte records from FIFO."""
        cmd = bytes([CMD_READFIFO, REG_VALUES_FIFO]) + struct.pack("<H", num_records)
        self._ser.write(cmd)

        expected = num_records * FIFO_RECORD_SIZE
        data = bytearray()
        start = time.time()

        while len(data) < expected and (time.time() - start) < timeout_s:
            chunk = self._ser.read(expected - len(data))
            if chunk:
                data.extend(chunk)
            else:
                time.sleep(0.02)

        records = []
        for i in range(len(data) // FIFO_RECORD_SIZE):
            offset = i * FIFO_RECORD_SIZE
            rec_bytes = data[offset:offset + FIFO_RECORD_SIZE]

            fwd0_re, fwd0_im = struct.unpack_from("<ii", rec_bytes, 0)
            rev0_re, rev0_im = struct.unpack_from("<ii", rec_bytes, 8)
            rev1_re, rev1_im = struct.unpack_from("<ii", rec_bytes, 16)
            freq_index = struct.unpack_from("<H", rec_bytes, 24)[0]

            records.append(FIFORecord(
                fwd0_re=fwd0_re, fwd0_im=fwd0_im,
                rev0_re=rev0_re, rev0_im=rev0_im,
                rev1_re=rev1_re, rev1_im=rev1_im,
                freq_index=freq_index,
            ))

        return records

    # ── Sweep configuration ──────────────────────────────────────────

    def configure_sweep(self, start_hz: int, stop_hz: int, points: int,
                        values_per_freq: int = 1) -> None:
        """Configure sweep parameters. This puts device into USB data mode."""
        self._ensure_connected()

        if points < 1:
            raise ValueError("points must be >= 1")
        if stop_hz < start_hz:
            raise ValueError("stop_hz must be >= start_hz")

        step_hz = (stop_hz - start_hz) // (points - 1) if points > 1 else 0

        self.clear_fifo()

        self._write8(REG_SWEEP_START, start_hz)
        self._write8(REG_SWEEP_STEP, step_hz)
        self._write2(REG_SWEEP_POINTS, points)
        self._write2(REG_VALUES_PER_F, values_per_freq)

        self._sweep_start = start_hz
        self._sweep_step = step_hz
        self._sweep_points = points

    # ── Acquisition ──────────────────────────────────────────────────

    def acquire_sweep(self, start_hz: int, stop_hz: int, points: int,
                      settle_s: float = 0.5) -> SweepResult:
        """Configure sweep, wait, clear stale data, read fresh FIFO.

        This is the main high-level acquisition method.
        """
        self.configure_sweep(start_hz, stop_hz, points)

        # Wait for device to run at least one full sweep
        time.sleep(settle_s)

        # Clear stale and read fresh
        self.clear_fifo()
        time.sleep(0.3)

        records = self._read_fifo(points)

        step_hz = (stop_hz - start_hz) // (points - 1) if points > 1 else 0

        return SweepResult(
            start_hz=start_hz,
            step_hz=step_hz,
            points=points,
            records=records,
        )

    def acquire_single(self, start_hz: int, stop_hz: int, points: int,
                       settle_s: float = 0.1) -> SweepResult:
        """Acquire one sweep using already-configured parameters.

        Use this for repeated acquisitions at same frequency settings
        (e.g., repeatability test, averaging). Assumes configure_sweep()
        was already called.

        Uses double-clear strategy: first clear discards stale data,
        wait for firmware to complete at least one full sweep cycle,
        second clear discards that (potentially partial) sweep,
        then read fresh complete sweep.
        """
        self._ensure_connected()
        time.sleep(settle_s)
        # Double-clear: discard stale + partial sweep
        self.clear_fifo()
        time.sleep(0.3)   # wait for one full sweep cycle
        self.clear_fifo()
        time.sleep(0.2)   # wait for fresh complete sweep
        records = self._read_fifo(self._sweep_points)
        return SweepResult(
            start_hz=self._sweep_start,
            step_hz=self._sweep_step,
            points=self._sweep_points,
            records=records,
        )

    # ── Context manager ──────────────────────────────────────────────

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.disconnect()
