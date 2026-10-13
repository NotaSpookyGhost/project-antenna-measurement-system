%% =========================================================================
%% PTIT ANTENNA LAB — ESP32 POSITIONER CONTROL INTERFACE FOR MATLAB
%% File: positioner_control.m
%% Mô tả: Lớp điều khiển trực tiếp bàn xoay Pan-Tilt qua USB Serial
%%        Giao thức: ESP32 DevKit V1, Baudrate 115200, kết thúc lệnh bằng LF
%%
%% Cách dùng nhanh:
%%   ctrl = positioner_control('COM3');   % Kết nối ESP32
%%   ctrl.goto(90, 45);                  % Xoay Pan=90°, Tilt=45°
%%   pos = ctrl.get_position();          % Đọc vị trí hiện tại
%%   ctrl.zero();                        % Đặt gốc tọa độ
%%   ctrl.close();                       % Đóng kết nối
%%
%% =========================================================================

classdef positioner_control < handle
    % ======================================================================
    % LỚP ĐIỀU KHIỂN BÀN XOAY PAN-TILT PTIT
    % Kết nối qua USB Serial tới ESP32 DevKit V1 (115200 baud)
    % ======================================================================

    properties (Access = private)
        sp          % Đối tượng serialport MATLAB
        port        % Tên cổng COM (vd: 'COM3', '/dev/ttyUSB0')
        connected   % Trạng thái kết nối
    end

    properties (Constant)
        BAUD_RATE   = 115200   % Baudrate cố định của ESP32
        STEPS_PER_DEG = 25.0  % Hệ số bước: 25 xung/° (TMC2209 1/8, Puly 16:90)
        SPEED_DEG_S   = 18.18 % Tốc độ hành trình ~18.18°/s (2200 µs/xung)
        SAFE_EXTRA_S  = 0.8   % Thời gian dự phòng sau khi motor dừng (giây)

        % Giới hạn góc an toàn
        PAN_MIN  =   0.0       % Azimuth tối thiểu (°)
        PAN_MAX  = 360.0       % Azimuth tối đa (°)
        TILT_MIN =   0.0       % Elevation tối thiểu (°)
        TILT_MAX =  90.0       % Elevation tối đa (°)
    end

    methods
        %% -------------------------------------------------------------------
        % Hàm khởi tạo — mở kết nối Serial tới ESP32
        % -------------------------------------------------------------------
        function obj = positioner_control(port_name)
            if nargin == 0 || isempty(port_name)
                port_name = 'COM3';
            end
            obj.port = port_name;
            obj.connected = false;

            fprintf('[Positioner] Đang kết nối tới ESP32 tại %s (115200)...\n', port_name);
            try
                obj.sp = serialport(port_name, obj.BAUD_RATE, "Timeout", 20);
                configureTerminator(obj.sp, "LF");
                flush(obj.sp);
                pause(2.0); % Chờ ESP32 khởi động lại sau khi DTR bật
                obj.connected = true;
                fprintf('[Positioner] ✅ Kết nối thành công!\n');

                % Đọc bất kỳ thông điệp khởi động nào từ ESP32
                pause(0.5);
                obj.flush_input();

            catch ME
                warning('[Positioner] ❌ Không mở được cổng %s: %s', port_name, ME.message);
                obj.connected = false;
            end
        end

        %% -------------------------------------------------------------------
        % goto(pan_deg, tilt_deg) — Di chuyển cả 2 trục đồng thời
        % -------------------------------------------------------------------
        function success = goto(obj, pan_deg, tilt_deg)
            success = false;
            if ~obj.connected, warning('[Positioner] Chưa kết nối!'); return; end

            % Kiểm tra giới hạn an toàn
            pan_deg  = max(obj.PAN_MIN,  min(obj.PAN_MAX,  pan_deg));
            tilt_deg = max(obj.TILT_MIN, min(obj.TILT_MAX, tilt_deg));

            % Đọc vị trí hiện tại để tính thời gian chờ
            current = obj.get_position();

            % Gửi lệnh GOTO
            cmd = sprintf('GOTO %.2f %.2f', pan_deg, tilt_deg);
            obj.send_cmd(cmd);

            % Tính thời gian chờ dựa trên góc di chuyển lớn nhất
            if ~isempty(current)
                delta_pan  = abs(pan_deg  - current.pan);
                delta_tilt = abs(tilt_deg - current.tilt);
                max_delta  = max(delta_pan, delta_tilt);
            else
                max_delta  = max(abs(pan_deg), abs(tilt_deg));
            end
            wait_sec = max_delta / obj.SPEED_DEG_S + obj.SAFE_EXTRA_S;

            fprintf('[Positioner] → GOTO Pan=%.1f° Tilt=%.1f° | Chờ %.1fs...\n', ...
                    pan_deg, tilt_deg, wait_sec);
            pause(wait_sec);
            success = true;
        end

        %% -------------------------------------------------------------------
        % pan_only(angle) — Chỉ xoay trục Azimuth
        % -------------------------------------------------------------------
        function success = pan_only(obj, angle_deg)
            success = false;
            if ~obj.connected, return; end
            angle_deg = max(obj.PAN_MIN, min(obj.PAN_MAX, angle_deg));
            obj.send_cmd(sprintf('PAN %.2f', angle_deg));
            current = obj.get_position();
            if isempty(current), delta = abs(angle_deg); else, delta = abs(angle_deg - current.pan); end
            pause(delta / obj.SPEED_DEG_S + obj.SAFE_EXTRA_S);
            success = true;
        end

        %% -------------------------------------------------------------------
        % tilt_only(angle) — Chỉ xoay trục Elevation
        % -------------------------------------------------------------------
        function success = tilt_only(obj, angle_deg)
            success = false;
            if ~obj.connected, return; end
            angle_deg = max(obj.TILT_MIN, min(obj.TILT_MAX, angle_deg));
            obj.send_cmd(sprintf('TILT %.2f', angle_deg));
            current = obj.get_position();
            if isempty(current), delta = abs(angle_deg); else, delta = abs(angle_deg - current.tilt); end
            pause(delta / obj.SPEED_DEG_S + obj.SAFE_EXTRA_S);
            success = true;
        end

        %% -------------------------------------------------------------------
        % get_position() — Đọc vị trí thực tế từ encoder AS5600
        % Trả về struct: .pan (°), .tilt (°), .raw_pan, .raw_tilt
        % -------------------------------------------------------------------
        function pos = get_position(obj)
            pos = [];
            if ~obj.connected, return; end

            obj.send_cmd('POS');
            pause(0.15);

            response = obj.read_line();
            if isempty(response), return; end

            % Parse response: "PAN:90.00 TILT:45.00 RAW_PAN:1024 RAW_TILT:512"
            tokens = regexp(response, ...
                'PAN:([\d.+-]+)\s+TILT:([\d.+-]+)\s+RAW_PAN:(\d+)\s+RAW_TILT:(\d+)', ...
                'tokens');
            if ~isempty(tokens)
                pos.pan      = str2double(tokens{1}{1});
                pos.tilt     = str2double(tokens{1}{2});
                pos.raw_pan  = str2double(tokens{1}{3});
                pos.raw_tilt = str2double(tokens{1}{4});
            else
                % Thử parse đơn giản hơn nếu format khác
                [pan_v, cnt] = sscanf(response, 'PAN:%f TILT:%f', 2);
                if cnt == 2
                    pos.pan  = pan_v(1);
                    pos.tilt = pan_v(2);
                    pos.raw_pan  = NaN;
                    pos.raw_tilt = NaN;
                end
            end
        end

        %% -------------------------------------------------------------------
        % zero() — Đặt vị trí hiện tại là gốc tọa độ (0°, 0°)
        % -------------------------------------------------------------------
        function zero(obj)
            if ~obj.connected, return; end
            obj.send_cmd('ZERO');
            pause(0.5);
            obj.flush_input();
            fprintf('[Positioner] ✅ Đã đặt gốc tọa độ ZERO.\n');
        end

        %% -------------------------------------------------------------------
        % home() — Đưa ăng-ten về vị trí an toàn (0°, 0°)
        % -------------------------------------------------------------------
        function home(obj)
            fprintf('[Positioner] → Đang về HOME (0°, 0°)...\n');
            obj.goto(0, 0);
        end

        %% -------------------------------------------------------------------
        % scan_test() — Chạy chu trình kiểm tra 4 điểm tự động
        % -------------------------------------------------------------------
        function scan_test(obj)
            if ~obj.connected, return; end
            fprintf('[Positioner] ▶ Bắt đầu chu trình SCAN kiểm tra...\n');
            obj.send_cmd('SCAN');
            pause(25); % Chu trình SCAN 4 điểm mất ~20-25 giây
            fprintf('[Positioner] ■ SCAN hoàn thành.\n');
        end

        %% -------------------------------------------------------------------
        % jog_motor(axis, steps) — Jog motor trực tiếp theo bước micro
        % axis: 1 = Pan, 2 = Tilt | steps: dương = thuận chiều
        % -------------------------------------------------------------------
        function jog_motor(obj, axis, steps)
            if ~obj.connected, return; end
            if axis == 1
                obj.send_cmd(sprintf('M1 %d', round(steps)));
            else
                obj.send_cmd(sprintf('M2 %d', round(steps)));
            end
            pause(abs(steps) / (obj.SPEED_DEG_S * obj.STEPS_PER_DEG) + 0.5);
        end

        %% -------------------------------------------------------------------
        % is_connected() — Kiểm tra trạng thái kết nối
        % -------------------------------------------------------------------
        function result = is_connected(obj)
            result = obj.connected;
        end

        %% -------------------------------------------------------------------
        % close() — Đóng kết nối Serial an toàn
        % -------------------------------------------------------------------
        function close(obj)
            if obj.connected && ~isempty(obj.sp)
                try
                    obj.home(); % Về vị trí an toàn
                    delete(obj.sp);
                catch
                end
                obj.connected = false;
                fprintf('[Positioner] Đã đóng kết nối Serial %s.\n', obj.port);
            end
        end
    end

    methods (Access = private)
        %% Gửi lệnh chuỗi xuống ESP32
        function send_cmd(obj, cmd_str)
            try
                writeline(obj.sp, cmd_str);
            catch ME
                warning('[Positioner] Lỗi gửi lệnh: %s', ME.message);
            end
        end

        %% Đọc 1 dòng phản hồi từ ESP32
        function line = read_line(obj)
            line = '';
            try
                if obj.sp.NumBytesAvailable > 0
                    line = strtrim(readline(obj.sp));
                end
            catch
            end
        end

        %% Xóa buffer Serial
        function flush_input(obj)
            try
                flush(obj.sp);
            catch
            end
        end
    end
end
