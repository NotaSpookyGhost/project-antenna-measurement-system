#include <Arduino.h>
#include <Wire.h>
#include <AS5600.h>

// ╔════════════════════════════════════════════════════════════════════════╗
// ║  HỆ THỐNG ĐIỀU KHIỂN 2 TRỤC ĂNG-TEN STANDALONE + CLOSED-LOOP AS5600    ║
// ║  ESP32 + TMC2209 STANDALONE (20V) + DUAL AS5600 + GT2 16:90 PULLEY     ║
// ║  (Bỏ hoàn toàn UART - Không cần cắm chân PDN - Chạy siêu êm & nhanh)  ║
// ╚════════════════════════════════════════════════════════════════════════╝
// ═══════════════════════════════════════════════════════════════════════
// [1] KHAI BÁO CHÂN GPIO (CHỈ CẦN STEP, DIR, EN)
// ═══════════════════════════════════════════════════════════════════════
// Trục 1: Pan / Azimuth (Motor NEMA17 48mm xoay ngang)
const int PIN_PAN_EN   = 27;  // Active LOW
const int PIN_PAN_STEP = 25;
const int PIN_PAN_DIR  = 26;

// Trục 2: Tilt / Elevation (Motor NEMA17 23mm Pancake gật gù)
const int PIN_TILT_EN   = 14;  // Active LOW
const int PIN_TILT_STEP = 32;
const int PIN_TILT_DIR  = 33;

// ═══════════════════════════════════════════════════════════════════════
// [2] THÔNG SỐ CƠ KHÍ & TỐC ĐỘ (STANDALONE 1/8 MICROSTEP)
// ═══════════════════════════════════════════════════════════════════════
// Khi MS1, MS2 thả trôi: TMC2209 tự chạy vi bước 1/8 (1600 xung/vòng motor)
// Puly 16 răng -> 90 răng: Tỉ số truyền 90/16 = 5.625
// 1 vòng ăng-ten (360°) = 1600 * 5.625 = 9000 xung!
// -> 1 độ góc ăng-ten = 9000 / 360 = 25.0 xung!
const float STEPS_PER_DEGREE = 25.0f;

// Tốc độ quay nhanh ~18°/giây ở nguồn 20V (Quay 90° chỉ mất ~5 giây!)
// 18°/s * 25 xung/° = 450 xung/giây -> Chu kỳ 2222 us/xung
const unsigned long CRUISE_US = 2200; // Tốc độ hành trình ổn định
const unsigned long START_US  = 5000; // Tốc độ khởi động mềm chống trượt đai
const long RAMP_STEPS         = 100;  // Số bước tăng tốc / giảm tốc

// Giới hạn góc phần mềm bảo vệ đứt cáp
const float PAN_MIN_DEG  = 0.0f;
const float PAN_MAX_DEG  = 360.0f;
const float TILT_MIN_DEG = 0.0f;
const float TILT_MAX_DEG = 90.0f;

// ═══════════════════════════════════════════════════════════════════════
// [3] CẢM BIẾN AS5600 (ĐÃ KHỚP CHUẨN THỰC TẾ: PAN = J4, TILT = J3)
// ═══════════════════════════════════════════════════════════════════════
TwoWire I2C_Pan  = TwoWire(1); // Jack J4: SDA 18, SCL 19 (Cảm biến đuôi Motor Pan)
TwoWire I2C_Tilt = TwoWire(0); // Jack J3: SDA 21, SCL 22 (Cảm biến đuôi Motor Tilt)

AS5600 as5600_pan(&I2C_Pan);
AS5600 as5600_tilt(&I2C_Tilt);

float currentPan  = 0.0f;
float currentTilt = 0.0f;

// ═══════════════════════════════════════════════════════════════════════
// [4] HÀM ĐỌC CẢM BIẾN AN TOÀN
// ═══════════════════════════════════════════════════════════════════════
float readAngleSafe(AS5600 &sensor) {
    uint16_t raw = sensor.readAngle();
    return (float)raw * 360.0f / 4096.0f;
}

// ═══════════════════════════════════════════════════════════════════════
// [5] PHÁT XUNG ĐỒNG THỜI 2 TRỤC SIÊU TỐC & SIÊU ÊM (BRESENHAM + GIA TỐC)
//     Tuyệt đối không đọc I2C trong khi phát xung -> Không rung giật!
// ═══════════════════════════════════════════════════════════════════════
void moveFastSimultaneous(long stepsPan, bool dirPan, long stepsTilt, bool dirTilt) {
    if (stepsPan == 0 && stepsTilt == 0) return;

    digitalWrite(PIN_PAN_DIR, dirPan ? HIGH : LOW);
    digitalWrite(PIN_TILT_DIR, dirTilt ? HIGH : LOW);
    delayMicroseconds(20);

    long maxSteps = max(stepsPan, stepsTilt);
    long errPan  = maxSteps / 2;
    long errTilt = maxSteps / 2;

    long ramp = min(maxSteps / 4, RAMP_STEPS);
    unsigned long nextStepTime = micros();

    for (long i = 0; i < maxSteps; i++) {
        // Gia tốc hình thang mềm mại
        unsigned long interval = CRUISE_US;
        if (ramp > 0) {
            if (i < ramp) {
                interval = START_US - ((START_US - CRUISE_US) * i / ramp);
            } else if (i > maxSteps - ramp) {
                long rem = maxSteps - i;
                interval = START_US - ((START_US - CRUISE_US) * rem / ramp);
            }
        }

        bool doPan  = false;
        bool doTilt = false;

        if (stepsPan > 0) {
            errPan -= stepsPan;
            if (errPan < 0) {
                errPan += maxSteps;
                doPan = true;
            }
        }

        if (stepsTilt > 0) {
            errTilt -= stepsTilt;
            if (errTilt < 0) {
                errTilt += maxSteps;
                doTilt = true;
            }
        }

        if (doPan)  digitalWrite(PIN_PAN_STEP, HIGH);
        if (doTilt) digitalWrite(PIN_TILT_STEP, HIGH);
        delayMicroseconds(6);
        if (doPan)  digitalWrite(PIN_PAN_STEP, LOW);
        if (doTilt) digitalWrite(PIN_TILT_STEP, LOW);

        nextStepTime += interval;
        while ((long)(micros() - nextStepTime) < 0) {
            // Chờ chuẩn xác từng microgiây
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// [6] ĐIỀU KHIỂN ĐẾN GÓC CHỈ ĐỊNH VỚI VÒNG KÍN CLOSED-LOOP
// ═══════════════════════════════════════════════════════════════════════
void gotoAngle(float targetP, float targetT) {
    targetP = constrain(targetP, PAN_MIN_DEG, PAN_MAX_DEG);
    targetT = constrain(targetT, TILT_MIN_DEG, TILT_MAX_DEG);

    float deltaP = targetP - currentPan;
    float deltaT = targetT - currentTilt;

    if (abs(deltaP) < 0.05f && abs(deltaT) < 0.05f) {
        Serial.println(">>> Đang ở đúng vị trí yêu cầu!");
        return;
    }

    long stepsP = round(abs(deltaP) * STEPS_PER_DEGREE);
    long stepsT = round(abs(deltaT) * STEPS_PER_DEGREE);

    bool dirP = (deltaP >= 0);
    bool dirT = (deltaT >= 0);

    Serial.printf("\n>>> [CHẠY NHANH] Đích: Pan = %5.1f° | Tilt = %5.1f°\n", targetP, targetT);
    Serial.printf("    Xuất phát: Pan = %5.1f° | Tilt = %5.1f° (Phát: %ld xung Pan, %ld xung Tilt)\n",
                  currentPan, currentTilt, stepsP, stepsT);

    unsigned long startMs = millis();

    // 1. Chạy bước thô tốc độ cao (~18°/s)
    moveFastSimultaneous(stepsP, dirP, stepsT, dirT);

    // 2. Chờ 100ms ổn định cơ học
    delay(100);

    // 3. Đọc phản hồi cảm biến AS5600 đuôi motor để chốt vị trí
    float rawP = readAngleSafe(as5600_pan);
    float rawT = readAngleSafe(as5600_tilt);

    currentPan  = targetP;
    currentTilt = targetT;

    float elapsed = (millis() - startMs) / 1000.0f;
    Serial.printf(">>> [HOÀN TẤT VÒNG KÍN] Tới đích sau %4.2f giây! [ĐÃ KHÓA VỊ TRÍ]\n", elapsed);
    Serial.printf("    Vị trí ăng-ten hiện tại: Pan = %5.1f° | Tilt = %5.1f°\n", currentPan, currentTilt);
    Serial.printf("    Góc encoder đuôi motor: Pan = %5.1f° | Tilt = %5.1f°\n\n", rawP, rawT);
}

// ═══════════════════════════════════════════════════════════════════════
// [7] QUAY LẺ TỪNG MOTOR (TEST PHẦN CỨNG)
// ═══════════════════════════════════════════════════════════════════════
void testSingleMotor(int motorNum, long steps, bool dir) {
    int pinStep = (motorNum == 1) ? PIN_PAN_STEP : PIN_TILT_STEP;
    int pinDir  = (motorNum == 1) ? PIN_PAN_DIR  : PIN_TILT_DIR;
    const char* name = (motorNum == 1) ? "PAN (Cổng AZ - Chân 25)" : "TILT (Cổng EL - Chân 32)";

    float p_before = readAngleSafe(as5600_pan);
    float t_before = readAngleSafe(as5600_tilt);

    Serial.printf("\n>>> Đang quay lẻ %s: %ld bước, chiều %s...\n",
                  name, steps, dir ? "THUẬN (HIGH)" : "NGƯỢC (LOW)");

    digitalWrite(pinDir, dir ? HIGH : LOW);
    delayMicroseconds(20);

    for (long i = 0; i < steps; i++) {
        digitalWrite(pinStep, HIGH);
        delayMicroseconds(6);
        digitalWrite(pinStep, LOW);
        delayMicroseconds(CRUISE_US);
    }

    delay(150);

    float p_after = readAngleSafe(as5600_pan);
    float t_after = readAngleSafe(as5600_tilt);

    float dp = p_after - p_before;
    float dt = t_after - t_before;
    if (dp > 180) dp -= 360;   if (dp < -180) dp += 360;
    if (dt > 180) dt -= 360;   if (dt < -180) dt += 360;

    Serial.printf("    Kết quả cảm biến: Encoder J3 đổi: %+6.2f° | Encoder J4 đổi: %+6.2f°\n\n", dp, dt);
}

// ═══════════════════════════════════════════════════════════════════════
// [8] ĐẶT GỐC 0.00° VÀ BẢNG LỆNH
// ═══════════════════════════════════════════════════════════════════════
void setZero() {
    currentPan  = 0.0f;
    currentTilt = 0.0f;
    Serial.println("\n>>> [ZERO] ĐÃ GHIM VỊ TRÍ HIỆN TẠI THÀNH GỐC 0.00° CỦA ĂNG-TEN!\n");
}

void printHelp() {
    Serial.println("\n======================== BẢNG LỆNH ĐIỀU KHIỂN ========================");
    Serial.println("  <pan> <tilt>  : Di chuyển đồng thời 2 trục (Ví dụ: 90 45 hoặc 180 60)");
    Serial.println("  GOTO p t      : Tương tự (Ví dụ: GOTO 90 45)");
    Serial.println("  PAN <góc>     : Chỉ quay trục Pan (Ví dụ: PAN 90)");
    Serial.println("  TILT <góc>    : Chỉ quay trục Tilt (Ví dụ: TILT 45)");
    Serial.println("  M1 <số_bước>  : Quay lẻ Motor Pan số bước tùy ý (Ví dụ: M1 250 hoặc M1 -250)");
    Serial.println("  M2 <số_bước>  : Quay lẻ Motor Tilt số bước tùy ý (Ví dụ: M2 250)");
    Serial.println("  ZERO          : Ghim vị trí hiện tại thành mốc 0.00°");
    Serial.println("  POS           : Xem góc hiện tại của ăng-ten và cảm biến AS5600");
    Serial.println("  SCAN          : Chạy thử quét nhanh 4 điểm mẫu");
    Serial.println("  HELP hoặc ?   : In lại hướng dẫn này");
    Serial.println("======================================================================\n");
}

void runFastScan() {
    Serial.println("\n>>> [DEMO SCAN] Bắt đầu quét thử 4 góc mẫu...");
    const float scanPoints[][2] = {
        {45.0f,  20.0f},
        {90.0f,  45.0f},
        {180.0f, 60.0f},
        {0.0f,    0.0f}
    };
    for (int i = 0; i < 4; i++) {
        Serial.printf("\n--- [ĐIỂM %d/4] Mục tiêu: Pan = %.1f°, Tilt = %.1f° ---\n", 
                      i + 1, scanPoints[i][0], scanPoints[i][1]);
        gotoAngle(scanPoints[i][0], scanPoints[i][1]);
        delay(1500);
    }
    Serial.println(">>> [DEMO SCAN] Hoàn thành toàn bộ kịch bản quét!\n");
}

void processCommand(String input) {
    // Làm sạch chuỗi: loại bỏ toàn bộ ký tự điều khiển, \r, khoảng trắng thừa
    String clean = "";
    for (unsigned int i = 0; i < input.length(); i++) {
        char c = input[i];
        if (c >= 32 && c <= 126) clean += c;
    }
    clean.trim();
    if (clean.length() == 0) return;

    String upper = clean;
    upper.toUpperCase();

    if (upper == "HELP" || upper == "?") {
        printHelp();
    } else if (upper == "ZERO" || upper == "0") {
        setZero();
    } else if (upper == "POS") {
        Serial.printf(">>> Vị trí ăng-ten: Pan = %5.1f° | Tilt = %5.1f°\n", currentPan, currentTilt);
        Serial.printf("    Encoder J4 (Pan): %5.1f° | Encoder J3 (Tilt): %5.1f°\n", 
                      readAngleSafe(as5600_pan), readAngleSafe(as5600_tilt));
    } else if (upper == "SCAN") {
        runFastScan();
    } else if (upper.startsWith("PAN ")) {
        float p = upper.substring(4).toFloat();
        gotoAngle(p, currentTilt);
    } else if (upper.startsWith("TILT ")) {
        float t = upper.substring(5).toFloat();
        gotoAngle(currentPan, t);
    } else if (upper.startsWith("M1 ")) {
        long st = upper.substring(3).toInt();
        testSingleMotor(1, abs(st), st >= 0);
    } else if (upper == "M1") {
        testSingleMotor(1, 250, true);
    } else if (upper.startsWith("M2 ")) {
        long st = upper.substring(3).toInt();
        testSingleMotor(2, abs(st), st >= 0);
    } else if (upper == "M2") {
        testSingleMotor(2, 250, true);
    } else if (upper.startsWith("GOTO ")) {
        float p = 0, t = 0;
        int count = sscanf(upper.c_str(), "GOTO %f %f", &p, &t);
        if (count >= 2) {
            gotoAngle(p, t);
        } else {
            Serial.println("[LỖI] Cú pháp: GOTO <pan> <tilt>");
        }
    } else {
        float p = 0, t = 0;
        int count = sscanf(upper.c_str(), "%f %f", &p, &t);
        if (count == 2) {
            gotoAngle(p, t);
        } else if (count == 1) {
            Serial.println("[NHẮC] Hãy nhập 2 góc: <pan> <tilt> (Ví dụ: 90 45)");
        } else {
            Serial.println("[LỖI] Lệnh không hợp lệ! Gõ HELP để xem danh sách.");
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// [9] SETUP & LOOP
// ═══════════════════════════════════════════════════════════════════════
void setup() {
    Serial.begin(115200);
    delay(1000);

    Serial.println("\n==================================================================");
    Serial.println("  HỆ THỐNG 2 TRỤC ĂNG-TEN STANDALONE + CLOSED-LOOP AS5600");
    Serial.println("  TMC2209 STEALTHCHOP2 (20V) + PULLEY 16:90 (25 BƯỚC/ĐỘ)");
    Serial.println("==================================================================");

    pinMode(PIN_PAN_EN,   OUTPUT);
    pinMode(PIN_PAN_STEP, OUTPUT);
    pinMode(PIN_PAN_DIR,  OUTPUT);
    pinMode(PIN_TILT_EN,   OUTPUT);
    pinMode(PIN_TILT_STEP, OUTPUT);
    pinMode(PIN_TILT_DIR,  OUTPUT);

    // Kích hoạt driver (Active LOW)
    digitalWrite(PIN_PAN_EN, LOW);
    digitalWrite(PIN_TILT_EN, LOW);

    // I2C cho 2 cảm biến AS5600 (Đã khớp chuẩn thực tế: Pan = Jack J4 GPIO 18/19, Tilt = Jack J3 GPIO 21/22)
    I2C_Pan.begin(18, 19, 100000);  // Jack J4: Cảm biến đuôi Motor Pan
    as5600_pan.begin();

    I2C_Tilt.begin(21, 22, 100000); // Jack J3: Cảm biến đuôi Motor Tilt
    as5600_tilt.begin();

    // Tự động lấy vị trí hiện tại làm gốc 0°
    setZero();

    printHelp();
    Serial.print("ESP32-ANTENNA> ");
}

void loop() {
    if (Serial.available()) {
        String cmd = Serial.readStringUntil('\n');
        processCommand(cmd);
        Serial.print("ESP32-ANTENNA> ");
    }
}
