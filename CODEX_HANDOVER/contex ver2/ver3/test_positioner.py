#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script kiểm tra tự động hệ thống bàn xoay ăng-ten 2 trục (Ver 3.0)
Hỗ trợ tự động nhận diện COM port hoặc chỉ định COM5.
"""

import sys
import io
import time
import serial
import serial.tools.list_ports

# Thiết lập UTF-8 cho Windows Terminal
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def find_ch340_port():
    ports = serial.tools.list_ports.comports()
    for p in ports:
        if 'CH340' in p.description or (p.vid == 0x1A86 and p.pid == 0x7523):
            return p.device
    return 'COM5'

def main():
    port_name = sys.argv[1] if len(sys.argv) > 1 else find_ch340_port()
    print(f"[*] Kết nối đến bàn xoay tại cổng: {port_name} (115200 Baud)")
    
    try:
        ser = serial.Serial(port_name, 115200, timeout=3.0)
    except Exception as e:
        print(f"[!] Lỗi không thể mở cổng {port_name}: {e}")
        return

    time.sleep(1.5)
    ser.read_all()

    def send_cmd(cmd, wait=1.0):
        print(f"\n>>> GỬI LỆNH: {cmd}")
        ser.write((cmd + '\n').encode('utf-8'))
        time.sleep(wait)
        resp = ser.read_all().decode('utf-8', errors='replace').strip()
        print(f"<<< PHẢN HỒI:\n{resp}")
        return resp

    print("\n--- 1. KIỂM TRA ĐỌC VỊ TRÍ & CẢM BIẾN ---")
    send_cmd("POS", 0.5)

    print("\n--- 2. THIẾT LẬP GỐC TỌA ĐỘ ---")
    send_cmd("ZERO", 0.5)

    print("\n--- 3. TEST QUAY ĐỒNG BỘ HAI TRỤC (GOTO 10 5) ---")
    send_cmd("GOTO 10 5", 2.0)
    send_cmd("POS", 0.5)

    print("\n--- 4. TEST QUAY VỀ GỐC (GOTO 0 0) ---")
    send_cmd("GOTO 0 0", 2.0)
    send_cmd("POS", 0.5)

    ser.close()
    print("\n[+] Đã hoàn thành toàn bộ bài kiểm tra thành công!")

if __name__ == '__main__':
    main()
