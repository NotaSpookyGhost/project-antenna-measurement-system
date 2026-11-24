# Firmware ESP32 moi nhat: V4.0_HOLD_FREE360

Ban dong goi ngay 2026-11-24 cho DOIT ESP32 DEVKIT V1, ESP32 classic, flash 4 MB.
Hai truc Pan va Tilt nhan goc tuyet doi -360..+360 do theo ZERO hien tai.
Co the quet 0 -> 360 va 360 -> 0. Day khong phai che do quay vo han nhieu vong.
Giu nguyen STOP, watchdog giu motor va kiem tra encoder.

## Nap file co san tren laptop Windows

1. Tai toan bo nhanh `codex/continuous-3d-shockline` va giai nen.
2. Dong app MATLAB/Serial Monitor dang giu cong ESP32. Cam ESP32 vao laptop.
3. Mo PowerShell trong thu muc nay. Cai esptool neu chua co:

```powershell
py -m pip install "esptool<5"
py -m serial.tools.list_ports
```

Thay `COM5` ben duoi bang cong ESP32 thuc te tren laptop:

```powershell
py -m esptool --chip esp32 --port COM5 --baud 115200 write_flash 0x0 esp32-free360-merged.bin
py -m esptool --chip esp32 --port COM5 --baud 115200 verify_flash 0x0 esp32-free360-merged.bin
```

`esp32-free360-merged.bin` da gom bootloader, partition table, boot_app0 va
ung dung: nap tai **0x0**. File `firmware.bin` chi la ung dung: nap tai
**0x10000** neu dung layout bootloader/partition da co tu ban nay. Khong nap
`firmware.bin` tai 0x0. Khong can xoa toan bo flash truoc khi nap.

## Mo app MATLAB cung ban

Tu thu muc goc repository, mo `Open Antenna App.vbs`, hoac trong MATLAB:

```matlab
addpath('matlab/classes','matlab/app');
app = AntennaMeasurementApp();
```

Chon ESP32 that, nhap cong COM cua laptop, Connect, roi **Khoa + ZERO**.
POS phai bao `FW:V4.0_HOLD_FREE360`, `FREE360_CAP:1`,
`PAN_MIN:-360 PAN_MAX:360 TILT_MIN:-360 TILT_MAX:360`.
App MATLAB trong nhanh nay nhan capability moi va bo gioi han Tilt -5..95 cu.
Goc theta 0..180 cua mo hinh 3D la quy tac toa do, khac voi dai quay motor EL.

## Build tu ma nguon (PlatformIO)

Tu thu muc goc repository:

```powershell
pio run -d firmware/positioner_v3_hold
pio run -d firmware/positioner_v3_hold -t upload --upload-port COM5
```

Nguon: `firmware/positioner_v3_hold/src/main.cpp`.
Board: `esp32doit-devkit-v1`; Espressif32 duoc pin o 7.1.3; toc do nap 115200 baud.
`manifest.json` ghi kich thuoc va SHA-256 cua cac file de doi chieu tai xuong.
