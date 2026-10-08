#!/usr/bin/env python3
"""
test_saa2n.py — Minimal proof-of-communication script for NanoVNA SAA-2N.

Purpose:
    Test the USB CDC link between PC and NanoVNA V2 (SAA-2N) using the
    binary register/FIFO protocol documented in NanoRFE UG1101.

Test sequence (from master-v4 §9.13 / §28):
    1. Auto-detect or manually specify COM port.
    2. Send INDICATE (0x0D) → expect 0x32 ('2').
    3. Read identity registers 0xF0..0xF4.
    4. Configure a small sweep around 2.4 GHz.
    5. Read N × 32-byte FIFO records.
    6. Compute complex S11/S21.
    7. Print structured log.

Usage:
    python test_saa2n.py              # auto-detect SAA-2N COM port
    python test_saa2n.py COM5         # specify port manually
    python test_saa2n.py --help

Dependencies:
    pip install pyserial
"""

import struct
import sys
import time

import serial
import serial.tools.list_ports


# ─── Protocol constants (VERIFIED from NanoRFE UG1101) ───────────────────

CMD_NOP       = 0x00
CMD_INDICATE  = 0x0D
CMD_READ      = 0x10   # read 1 byte
CMD_READ2     = 0x11   # read 2 bytes
CMD_READ4     = 0x12   # read 4 bytes
CMD_READFIFO  = 0x18   # read N records from FIFO
CMD_WRITE     = 0x20   # write 1 byte
CMD_WRITE2    = 0x21   # write 2 bytes
CMD_WRITE4    = 0x22   # write 4 bytes
CMD_WRITE8    = 0x23   # write 8 bytes
CMD_WRITEFIFO = 0x28   # write data into FIFO

# Register addresses
REG_SWEEP_START    = 0x00  # uint64
REG_SWEEP_STEP     = 0x10  # uint64
REG_SWEEP_POINTS   = 0x20  # uint16
REG_VALUES_PER_F   = 0x22  # uint16
REG_VALUES_FIFO    = 0x30  # FIFO
REG_DEVICE_VARIANT = 0xF0  # uint8 — V2 = 0x02
REG_PROTOCOL_VER   = 0xF1  # uint8 — V2 wire = 0x01
REG_HW_REVISION    = 0xF2  # uint8
REG_FW_MAJOR       = 0xF3  # uint8
REG_FW_MINOR       = 0xF4  # uint8

FIFO_RECORD_SIZE = 32  # bytes per FIFO record

# ─── Sweep parameters for test ───────────────────────────────────────────

SWEEP_CENTER_HZ = 2_400_000_000   # 2.4 GHz
SWEEP_SPAN_HZ   = 10_000_000      # ±5 MHz → 10 MHz span
SWEEP_POINTS    = 11               # small number for quick test


# ─── Low-level protocol helpers ──────────────────────────────────────────

def send_indicate(ser: serial.Serial) -> bool:
    """Send INDICATE command and check for '2' (0x32) response."""
    ser.reset_input_buffer()
    ser.write(bytes([CMD_INDICATE]))
    resp = ser.read(1)
    if len(resp) == 1 and resp[0] == 0x32:
        return True
    return False


def read_register_1(ser: serial.Serial, addr: int) -> int:
    """Read 1-byte register."""
    ser.write(bytes([CMD_READ, addr]))
    data = ser.read(1)
    if len(data) != 1:
        raise TimeoutError(f"Timeout reading register 0x{addr:02X}")
    return data[0]


def read_register_2(ser: serial.Serial, addr: int) -> int:
    """Read 2-byte register (little-endian)."""
    ser.write(bytes([CMD_READ2, addr]))
    data = ser.read(2)
    if len(data) != 2:
        raise TimeoutError(f"Timeout reading register 0x{addr:02X}")
    return struct.unpack("<H", data)[0]


def read_register_4(ser: serial.Serial, addr: int) -> int:
    """Read 4-byte register (little-endian)."""
    ser.write(bytes([CMD_READ4, addr]))
    data = ser.read(4)
    if len(data) != 4:
        raise TimeoutError(f"Timeout reading register 0x{addr:02X}")
    return struct.unpack("<I", data)[0]


def write_register_1(ser: serial.Serial, addr: int, val: int):
    """Write 1-byte register."""
    ser.write(bytes([CMD_WRITE, addr, val & 0xFF]))


def write_register_2(ser: serial.Serial, addr: int, val: int):
    """Write 2-byte register (little-endian)."""
    ser.write(bytes([CMD_WRITE2, addr]) + struct.pack("<H", val))


def write_register_8(ser: serial.Serial, addr: int, val: int):
    """Write 8-byte register (little-endian uint64)."""
    ser.write(bytes([CMD_WRITE8, addr]) + struct.pack("<Q", val))


def flush_fifo(ser: serial.Serial):
    """Clear stale FIFO data by writing a dummy value to FIFO address.
    Per UG1101: write any value to 0x30 to clear."""
    ser.write(bytes([CMD_WRITE, REG_VALUES_FIFO, 0x00]))
    time.sleep(0.1)
    ser.reset_input_buffer()


def read_fifo(ser: serial.Serial, num_records: int) -> bytes:
    """Read num_records × 32-byte FIFO records."""
    # READFIFO command: opcode(1) + addr(1) + count(2, little-endian)
    # count = number of 32-byte records
    cmd = bytes([CMD_READFIFO, REG_VALUES_FIFO]) + struct.pack("<H", num_records)
    ser.write(cmd)
    
    expected_bytes = num_records * FIFO_RECORD_SIZE
    data = bytearray()
    
    # Read with retries — FIFO may take time to fill
    max_wait = 10.0  # seconds
    start = time.time()
    while len(data) < expected_bytes and (time.time() - start) < max_wait:
        chunk = ser.read(expected_bytes - len(data))
        if chunk:
            data.extend(chunk)
        else:
            time.sleep(0.05)
    
    return bytes(data)


def parse_fifo_record(record: bytes) -> dict:
    """Parse a single 32-byte FIFO record.
    
    Format (VERIFIED UG1101):
        0x00..03  fwd0Re      int32
        0x04..07  fwd0Im      int32
        0x08..0B  rev0Re      int32
        0x0C..0F  rev0Im      int32
        0x10..13  rev1Re      int32
        0x14..17  rev1Im      int32
        0x18..19  freqIndex   uint16
        0x1A..1F  reserved    6 bytes
    """
    if len(record) != 32:
        raise ValueError(f"Record size {len(record)} != 32")
    
    fwd0_re, fwd0_im = struct.unpack_from("<ii", record, 0)
    rev0_re, rev0_im = struct.unpack_from("<ii", record, 8)
    rev1_re, rev1_im = struct.unpack_from("<ii", record, 16)
    freq_index = struct.unpack_from("<H", record, 24)[0]
    
    return {
        "fwd0_re": fwd0_re, "fwd0_im": fwd0_im,
        "rev0_re": rev0_re, "rev0_im": rev0_im,
        "rev1_re": rev1_re, "rev1_im": rev1_im,
        "freq_index": freq_index,
    }


# ─── Auto-detect SAA-2N ─────────────────────────────────────────────────

def find_nanovna_port() -> str | None:
    """Try to find SAA-2N / NanoVNA V2 among available COM ports.
    
    SAA-2N typically shows up as a USB CDC device. We look for ports 
    that are NOT Bluetooth and try INDICATE on each candidate.
    """
    ports = serial.tools.list_ports.comports()
    candidates = []
    for p in ports:
        desc_lower = (p.description or "").lower()
        # Skip Bluetooth ports
        if "bluetooth" in desc_lower:
            continue
        candidates.append(p.device)
    
    if not candidates:
        return None
    
    # Try INDICATE on each candidate
    for port in candidates:
        try:
            with serial.Serial(port, baudrate=115200, timeout=1) as ser:
                time.sleep(0.2)
                if send_indicate(ser):
                    return port
        except (serial.SerialException, OSError):
            continue
    
    return None


# ─── Main test sequence ─────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  SAA-2N / NanoVNA V2 — Proof of Communication Test")
    print("  Protocol: USB CDC + binary register/FIFO (UG1101)")
    print("=" * 60)
    print()
    
    # ── Step 0: Determine COM port ──────────────────────────────────
    if len(sys.argv) > 1:
        if sys.argv[1] in ("--help", "-h"):
            print(__doc__)
            return
        port = sys.argv[1]
        print(f"[PORT] Using specified port: {port}")
    else:
        print("[PORT] Auto-detecting SAA-2N...")
        print("       Available ports:")
        for p in serial.tools.list_ports.comports():
            print(f"         {p.device} — {p.description}")
        port = find_nanovna_port()
        if port is None:
            print()
            print("[FAIL] SAA-2N not found. Please:")
            print("       1. Connect SAA-2N via USB")
            print("       2. Check Device Manager for new COM port")
            print("       3. Run:  python test_saa2n.py COMx")
            return
        print(f"       → Detected: {port}")
    
    print()
    
    # ── Open serial connection ──────────────────────────────────────
    try:
        ser = serial.Serial(
            port=port,
            baudrate=115200,
            timeout=2,
            write_timeout=2,
        )
    except serial.SerialException as e:
        print(f"[FAIL] Cannot open {port}: {e}")
        return
    
    time.sleep(0.3)  # let device settle after open
    
    try:
        # ── Step 1: INDICATE handshake ──────────────────────────────
        print("[TEST 1] INDICATE handshake")
        print(f"         TX: 0x0D")
        
        ser.reset_input_buffer()
        ser.write(bytes([CMD_INDICATE]))
        resp = ser.read(1)
        
        if len(resp) == 1 and resp[0] == 0x32:
            print(f"         RX: 0x{resp[0]:02X} (ASCII '2')")
            print(f"         ✓ PASS")
        else:
            rx_hex = resp.hex() if resp else "(no response)"
            print(f"         RX: {rx_hex}")
            print(f"         ✗ FAIL — expected 0x32, device may not be SAA-2N")
            return
        
        print()
        
        # ── Step 2: Read identity registers ─────────────────────────
        print("[TEST 2] Identity registers (0xF0..0xF4)")
        
        device_variant   = read_register_1(ser, REG_DEVICE_VARIANT)
        protocol_version = read_register_1(ser, REG_PROTOCOL_VER)
        hw_revision      = read_register_1(ser, REG_HW_REVISION)
        fw_major         = read_register_1(ser, REG_FW_MAJOR)
        fw_minor         = read_register_1(ser, REG_FW_MINOR)
        
        print(f"         deviceVariant    = 0x{device_variant:02X}" + 
              (" ← V2 ✓" if device_variant == 0x02 else " ← unexpected!"))
        print(f"         protocolVersion  = 0x{protocol_version:02X}" +
              (" ← V2 wire ✓" if protocol_version == 0x01 else ""))
        print(f"         hardwareRevision = 0x{hw_revision:02X} ({hw_revision})")
        print(f"         firmwareMajor    = 0x{fw_major:02X} ({fw_major})")
        print(f"         firmwareMinor    = 0x{fw_minor:02X} ({fw_minor})")
        
        if device_variant == 0x02:
            print(f"         ✓ PASS — confirmed NanoVNA V2")
        else:
            print(f"         ⚠ WARNING — deviceVariant is not 0x02")
        
        print()
        
        # ── Step 3: Configure sweep ─────────────────────────────────
        start_hz = SWEEP_CENTER_HZ - SWEEP_SPAN_HZ // 2
        step_hz = SWEEP_SPAN_HZ // (SWEEP_POINTS - 1) if SWEEP_POINTS > 1 else SWEEP_SPAN_HZ
        stop_hz = start_hz + step_hz * (SWEEP_POINTS - 1)
        
        print("[TEST 3] Configure sweep")
        print(f"         center = {SWEEP_CENTER_HZ / 1e6:.1f} MHz")
        print(f"         start  = {start_hz / 1e6:.1f} MHz")
        print(f"         stop   = {stop_hz / 1e6:.1f} MHz")
        print(f"         step   = {step_hz / 1e3:.1f} kHz")
        print(f"         points = {SWEEP_POINTS}")
        
        # Flush old FIFO data
        flush_fifo(ser)
        
        # Write sweep parameters — this puts device into USB data mode
        write_register_8(ser, REG_SWEEP_START, start_hz)
        write_register_8(ser, REG_SWEEP_STEP, step_hz)
        write_register_2(ser, REG_SWEEP_POINTS, SWEEP_POINTS)
        write_register_2(ser, REG_VALUES_PER_F, 1)  # 1 value per frequency
        
        print(f"         ✓ Sweep configured")
        print()
        
        # ── Step 4: Wait for sweep and read FIFO ────────────────────
        print("[TEST 4] Read FIFO records")
        print(f"         Waiting for {SWEEP_POINTS} × 32-byte records...")
        
        # Give device time to start sweep
        time.sleep(0.5)
        
        # Flush FIFO again to get fresh data
        flush_fifo(ser)
        
        # Wait for sweep to complete
        time.sleep(1.0)
        
        fifo_data = read_fifo(ser, SWEEP_POINTS)
        
        received_records = len(fifo_data) // FIFO_RECORD_SIZE
        remaining_bytes = len(fifo_data) % FIFO_RECORD_SIZE
        
        print(f"         expected_records = {SWEEP_POINTS}")
        print(f"         received_bytes   = {len(fifo_data)}")
        print(f"         received_records = {received_records}")
        print(f"         remainder_bytes  = {remaining_bytes}")
        
        if received_records < SWEEP_POINTS:
            print(f"         ⚠ WARNING — got fewer records than requested")
            print(f"           This may indicate the sweep hasn't completed yet")
            print(f"           or a communication issue.")
            if received_records == 0:
                print(f"         ✗ FAIL — no FIFO data received")
                return
        
        if remaining_bytes != 0:
            print(f"         ⚠ WARNING — non-aligned data ({remaining_bytes} extra bytes)")
        
        print(f"         ✓ FIFO read complete ({received_records} records)")
        print()
        
        # ── Step 5: Parse and compute S11/S21 ───────────────────────
        print("[TEST 5] Parse FIFO → compute S11/S21")
        print()
        print(f"  {'#':>3}  {'freq_idx':>8}  {'Freq (MHz)':>11}  "
              f"{'|S11| dB':>9}  {'|S21| dB':>9}  {'FWD0':>14}  {'REV0':>14}  {'REV1':>14}")
        print(f"  {'─'*3}  {'─'*8}  {'─'*11}  {'─'*9}  {'─'*9}  {'─'*14}  {'─'*14}  {'─'*14}")
        
        import math
        
        results = []
        for i in range(received_records):
            offset = i * FIFO_RECORD_SIZE
            record = fifo_data[offset:offset + FIFO_RECORD_SIZE]
            fields = parse_fifo_record(record)
            
            # Complex wave values
            fwd0 = complex(fields["fwd0_re"], fields["fwd0_im"])
            rev0 = complex(fields["rev0_re"], fields["rev0_im"])
            rev1 = complex(fields["rev1_re"], fields["rev1_im"])
            
            # Compute S-parameters (VERIFIED: UG1101 §9.5)
            if abs(fwd0) > 0:
                s11 = rev0 / fwd0
                s21 = rev1 / fwd0
            else:
                s11 = complex(0, 0)
                s21 = complex(0, 0)
            
            # Magnitude in dB
            s11_db = 20 * math.log10(abs(s11)) if abs(s11) > 0 else -999.0
            s21_db = 20 * math.log10(abs(s21)) if abs(s21) > 0 else -999.0
            
            # Frequency from index
            freq_hz = start_hz + fields["freq_index"] * step_hz
            
            results.append({
                "freq_index": fields["freq_index"],
                "freq_hz": freq_hz,
                "s11": s11,
                "s21": s21,
                "s11_db": s11_db,
                "s21_db": s21_db,
            })
            
            print(f"  {i:3d}  {fields['freq_index']:8d}  {freq_hz/1e6:11.3f}  "
                  f"{s11_db:9.2f}  {s21_db:9.2f}  "
                  f"{abs(fwd0):14.0f}  {abs(rev0):14.0f}  {abs(rev1):14.0f}")
        
        print()
        
        # ── Summary ─────────────────────────────────────────────────
        print("=" * 60)
        print("  SUMMARY")
        print("=" * 60)
        print(f"  PORT             = {port}")
        print(f"  deviceVariant    = 0x{device_variant:02X}")
        print(f"  protocolVersion  = 0x{protocol_version:02X}")
        print(f"  hardwareRevision = {hw_revision}")
        print(f"  firmware         = {fw_major}.{fw_minor}")
        print(f"  sweep            = {start_hz/1e6:.1f}–{stop_hz/1e6:.1f} MHz, {SWEEP_POINTS} pts")
        print(f"  FIFO records     = {received_records}/{SWEEP_POINTS}")
        
        if results:
            s11_vals = [r["s11_db"] for r in results if r["s11_db"] > -900]
            s21_vals = [r["s21_db"] for r in results if r["s21_db"] > -900]
            if s11_vals:
                print(f"  S11 range        = {min(s11_vals):.1f} .. {max(s11_vals):.1f} dB")
            if s21_vals:
                print(f"  S21 range        = {min(s21_vals):.1f} .. {max(s21_vals):.1f} dB")
        
        print()
        if received_records == SWEEP_POINTS:
            print("  ✓ ALL TESTS PASSED — SAA-2N communication verified!")
        else:
            print(f"  ⚠ PARTIAL — {received_records}/{SWEEP_POINTS} records received")
        
        print()
        print("  Next steps:")
        print("    1. Connect a known DUT (antenna/cable/thru)")
        print("    2. Compare S11/S21 with NanoVNA-QT or NanoVNA-Saver")
        print("    3. If results match → proceed to MATLAB bridge")
        print("=" * 60)
    
    finally:
        ser.close()
        print(f"\n[PORT] {port} closed.")


if __name__ == "__main__":
    main()
