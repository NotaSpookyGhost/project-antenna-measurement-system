classdef AntennaMeasurementApp < handle
    % ANTENNAMEASUREMENTAPP Interactive Automated Antenna Measurement Application
    %
    % Complete MATLAB measurement application for NanoVNA SAA-2N + 2-Axis Positioner.
    % Follows Master Document §15 & §16 specifications:
    %   - Dual Hardware/Mock mode selection for both VNA and Positioner
    %   - Configurable center frequency, span, sweep points, angular range & step
    %   - Real-time live Polar, Cartesian, S11/S21 trace, and 3D pattern updates
    %   - Dedicated 'System & Hardware Logs' Tab with full console and export
    %   - Live numerical metrics: Peak Angle, Peak S21, HPBW, SLL, and FBR
    %   - Export and Reload functions via DataManager (MAT, CSV, JSON, PNG)
    %   - Automatic auto-connect & Tilt driver protection guards
    %
    % Usage:
    %   app = AntennaMeasurementApp();
    %   % (Opens interactive graphical application)

    properties
        Figure

        % Subsystems
        VNA VNAController
        Positioner PositionerController
        Orchestrator MeasurementOrchestrator

        % UI Components - Inputs
        VNAModeDropdown
        VNAPortEdit
        VNAConnectBtn
        VNALamp

        PosModeDropdown
        PosPortEdit
        PosConnectBtn
        PosLamp
        HomeBtn

        CenterFreqEdit
        SpanEdit
        SweepPointsEdit

        StartAngleEdit
        StopAngleEdit
        StepAngleEdit
        AxisDropdown
        SettleTimeEdit

        StartScanBtn
        PauseBtn
        StopBtn

        % Metric labels
        PeakAngleLabel
        PeakS21Label
        HPBWLabel
        SLLLabel
        FBRLabel

        % Visualization
        TabGroup
        PolarTab
        CartTab
        RFMonitorTab
        ThreeDTab
        LogTab

        PolarAx
        CartAx
        RFMonitorAx1
        RFMonitorAx2
        ThreeDAx
        LogConsoleBox
        LogCountLabel

        % Status & Progress
        ProgressBar
        StatusLabel
        LogListBox

        % Live Data Cache
        LiveAngles double = []
        LiveS21_dB double = []
        LastScanData struct = struct()
    end

    methods
        function obj = AntennaMeasurementApp()
            % Constructor: Add classes to path and build UI
            matlab_dir = fileparts(fileparts(mfilename('fullpath')));
            addpath(fullfile(matlab_dir, 'classes'));

            obj.VNA = VNAController('Mode', 'Mock');
            obj.Positioner = PositionerController('Mode', 'Mock');
            obj.Orchestrator = MeasurementOrchestrator(obj.VNA, obj.Positioner);

            obj.createUI();
            obj.updateConnectionStatus();
            obj.log('Antenna Measurement App initialized.');
        end

        function delete(obj)
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end
            if ~isempty(obj.VNA)
                delete(obj.VNA);
            end
            if ~isempty(obj.Positioner)
                delete(obj.Positioner);
            end
        end

        function startScan(obj)
            % START SCAN CALLBACK
            if obj.Orchestrator.IsRunning
                return;
            end

            % Read UI Parameters
            center_mhz = str2double(obj.CenterFreqEdit.String);
            span_mhz   = str2double(obj.SpanEdit.String);
            pts        = str2double(obj.SweepPointsEdit.String);
            start_ang  = str2double(obj.StartAngleEdit.String);
            stop_ang   = str2double(obj.StopAngleEdit.String);
            step_ang   = str2double(obj.StepAngleEdit.String);
            settle_s   = str2double(obj.SettleTimeEdit.String);

            % Angular and sweep input validation
            if isnan(start_ang) || isnan(stop_ang) || isnan(step_ang)
                errordlg('Góc quét (Start, Stop, Step) phải là giá trị số hợp lệ!', 'Tham số không hợp lệ');
                return;
            end
            if start_ang < -360 || start_ang > 360 || stop_ang < -360 || stop_ang > 360
                errordlg('Góc Start và Stop phải nằm trong khoảng [-360°, +360°]!', 'Giới hạn góc quét');
                return;
            end
            if step_ang <= 0
                errordlg('Bước góc (Step) phải lớn hơn 0°! Hệ thống tự động xác định chiều quay (CW/CCW) từ Start và Stop.', 'Bước góc không hợp lệ');
                return;
            end
            if abs(start_ang - stop_ang) < 1e-4
                errordlg('Góc Start và Stop không được trùng nhau!', 'Phạm vi quét không hợp lệ');
                return;
            end
            if isnan(pts) || pts < 2
                errordlg('Số điểm quét VNA (Points) phải >= 2!', 'Tham số VNA không hợp lệ');
                return;
            end
            if isnan(settle_s) || settle_s < 0
                settle_s = 0.2;
            end

            axis_idx = obj.AxisDropdown.Value;
            axis_choices = {'AZ', 'EL'};
            scan_axis = axis_choices{axis_idx};

            % Auto-connect Positioner if not connected
            if ~obj.Positioner.IsConnected
                port = strtrim(obj.PosPortEdit.String);
                if isempty(port), port = 'COM9'; end
                try
                    obj.log(sprintf('⚠️ Positioner chưa kết nối! Đang tự động kết nối tới %s...', port));
                    obj.Positioner.connect(port);
                    obj.updateConnectionStatus();
                catch ME
                    obj.log(sprintf('❌ Lỗi kết nối Positioner: %s', ME.message));
                    errordlg(sprintf('Không thể kết nối Positioner trên %s: %s', port, ME.message), 'Connection Error');
                    if ~isempty(obj.LogTab) && isvalid(obj.LogTab)
                        obj.TabGroup.SelectedTab = obj.LogTab;
                    end
                    return;
                end
            end

            % Hardware safety lock check: Tilt driver protection
            if strcmp(scan_axis, 'EL') && obj.Positioner.TiltDisabled
                errMsg = 'Trục Tilt đang bị KHÓA BẢO VỆ do driver TMC bị cháy. Vui lòng chuyển Scan Axis về Azimuth (AZ)!';
                obj.log(sprintf('⚠️ %s', errMsg));
                errordlg(errMsg, 'Hardware Protection');
                if ~isempty(obj.LogTab) && isvalid(obj.LogTab)
                    obj.TabGroup.SelectedTab = obj.LogTab;
                end
                return;
            end

            obj.Orchestrator.setScanParameters(start_ang, stop_ang, step_ang, ...
                                               center_mhz * 1e6, span_mhz * 1e6, pts);
            obj.Orchestrator.Axis = scan_axis;
            obj.Orchestrator.SettleTimeSec = settle_s;

            % Set up Real-time Step Callback
            obj.LiveAngles = [];
            obj.LiveS21_dB = [];
            cla(obj.PolarAx);
            cla(obj.CartAx);

            obj.Orchestrator.StepCallback = @(info) obj.handleStepProgress(info);
            obj.Orchestrator.StatusCallback = @(msg) obj.log(msg);

            % Update UI State
            obj.StartScanBtn.Enable = 'off';
            obj.PauseBtn.Enable = 'on';
            obj.PauseBtn.String = 'Pause';
            obj.StopBtn.Enable = 'on';
            obj.StopBtn.String = 'STOP';

            % Run scan
            try
                scanData = obj.Orchestrator.startScan();
                if isempty(scanData)
                    obj.log('⚠️ Quá trình quét đã bị hủy hoặc không đủ dữ liệu (cần >= 2 điểm).');
                else
                    obj.LastScanData = scanData;
                    obj.updateFinalResults(scanData);
                    if isfield(scanData, 'Metadata') && isfield(scanData.Metadata, 'Aborted') && scanData.Metadata.Aborted
                        obj.log(sprintf('⚠️ Quét đã dừng bởi người dùng (đã ghi nhận %d/%d điểm). Dữ liệu đã lưu tạm cho phân tích/xuất file.', ...
                            scanData.Metadata.CompletedPoints, scanData.Metadata.TotalAngles));
                    end
                end
            catch ME
                obj.log(sprintf('❌ Lỗi trong quá trình quét: %s', ME.message));
                errordlg(sprintf('Lỗi quét: %s', ME.message), 'Scan Error');
                if ~isempty(obj.LogTab) && isvalid(obj.LogTab)
                    obj.TabGroup.SelectedTab = obj.LogTab;
                end
            end

            obj.StartScanBtn.Enable = 'on';
            obj.PauseBtn.Enable = 'off';
            obj.PauseBtn.String = 'Pause';
            obj.StopBtn.Enable = 'off';
            obj.StopBtn.String = 'STOP';
            obj.updateProgress(0.0);
        end

        function togglePause(obj)
            if obj.Orchestrator.IsPaused
                obj.Orchestrator.resumeScan();
                obj.PauseBtn.String = 'Pause';
            else
                obj.Orchestrator.pauseScan();
                obj.PauseBtn.String = 'Resume';
            end
        end

        function abortScan(obj)
            obj.log('⚠️ Đang gửi lệnh dừng quét (STOP)...');
            obj.StopBtn.String = 'Stopping...';
            obj.StopBtn.Enable = 'off';
            obj.PauseBtn.Enable = 'off';
            drawnow;
            obj.Orchestrator.abortScan();
        end

        function exportCurrentData(obj)
            if isempty(fieldnames(obj.LastScanData))
                errordlg('No scan data available to export. Run a scan first.', 'Export Error');
                return;
            end
            matlab_dir = fileparts(fileparts(mfilename('fullpath')));
            projects_dir = fileparts(matlab_dir);
            base_dir = fullfile(projects_dir, 'data', 'scans');

            exp_dir = DataManager.createScanDirectory(base_dir, 'export_app_scan');
            fig_export = figure('Visible', 'off', 'Position', [100 100 1000 480]);
            ax1 = subplot(1, 2, 1, polaraxes);
            PatternAnalyzer.plotPolar(ax1, obj.LastScanData.Angles, obj.LastScanData.NormalizedS21_dB, ...
                sprintf('Polar Pattern — %.3f GHz', obj.LastScanData.SelectedFreqHz/1e6));
            ax2 = subplot(1, 2, 2);
            PatternAnalyzer.plotCartesian(ax2, obj.LastScanData.Angles, obj.LastScanData.NormalizedS21_dB, ...
                sprintf('Cartesian Pattern (HPBW: %.1f°, SLL: %.1f dB)', ...
                        obj.LastScanData.Analysis.HPBW_deg, obj.LastScanData.Analysis.SLL_dB));
            DataManager.saveScanDataset(exp_dir, obj.LastScanData, fig_export);
            close(fig_export);

            msgbox(sprintf('Dataset successfully exported to:\n%s', exp_dir), 'Export Success');
            obj.log(sprintf('Exported dataset to: %s', exp_dir));
        end

        function loadDataset(obj)
            [file, path] = uigetfile('*.mat', 'Select scan_data.mat file');
            if isequal(file, 0), return; end
            full_path = fullfile(path, file);
            try
                loaded = DataManager.loadScanDataset(full_path);
                obj.LastScanData = loaded;
                obj.updateFinalResults(loaded);
                obj.log(sprintf('Loaded dataset from: %s', full_path));
            catch ME
                errordlg(sprintf('Failed to load dataset: %s', ME.message), 'Load Error');
            end
        end
    end

    methods
        function createUI(obj)
            % Build complete GUI window
            figW = 1200; figH = 780;
            screen = get(0, 'ScreenSize');
            posX = max((screen(3) - figW) / 2, 50);
            posY = max((screen(4) - figH) / 2, 50);

            obj.Figure = figure('Name', 'Automatic Antenna Measurement System — NanoVNA SAA-2N', ...
                                'Position', [posX, posY, figW, figH], ...
                                'NumberTitle', 'off', ...
                                'MenuBar', 'none', ...
                                'Color', [0.94 0.95 0.96]);

            % ── Left Control Panel (x=10, w=360) ─────────────────────────
            ctrlPanel = uipanel(obj.Figure, 'Title', 'Control & Setup', ...
                                'FontWeight', 'bold', 'FontSize', 10, ...
                                'Units', 'pixels', 'Position', [10, 65, 360, 705], ...
                                'BackgroundColor', 'w');

            % 1. VNA Connection Group
            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'VNA Interface:', ...
                      'FontWeight', 'bold', 'Position', [10, 615, 100, 20], ...
                      'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

            obj.VNAModeDropdown = uicontrol(ctrlPanel, 'Style', 'popupmenu', ...
                                            'String', {'Mock (Simulated SAA-2N)', 'Real (USB COM6)'}, ...
                                            'Position', [120, 615, 160, 22], ...
                                            'Callback', @(~,~) obj.handleVNAModeChange());

            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Port:', ...
                      'Position', [10, 585, 40, 20], 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
            obj.VNAPortEdit = uicontrol(ctrlPanel, 'Style', 'edit', 'String', 'COM6', ...
                                        'Position', [50, 585, 70, 22]);

            obj.VNAConnectBtn = uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', 'Connect', ...
                                          'Position', [130, 585, 80, 24], ...
                                          'BackgroundColor', [0.2 0.6 0.2], 'ForegroundColor', 'w', ...
                                          'FontWeight', 'bold', ...
                                          'Callback', @(~,~) obj.toggleVNAConnect());

            obj.VNALamp = uicontrol(ctrlPanel, 'Style', 'text', 'String', 'OFFLINE', ...
                                    'Position', [220, 587, 80, 20], 'Enable', 'inactive', ...
                                    'BackgroundColor', [0.8 0.8 0.8], 'FontWeight', 'bold');

            % 2. Positioner Connection Group
            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Positioner:', ...
                      'FontWeight', 'bold', 'Position', [10, 550, 100, 20], ...
                      'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

            obj.PosModeDropdown = uicontrol(ctrlPanel, 'Style', 'popupmenu', ...
                                            'String', {'Mock (Simulated L-Frame)', 'Hardware (ESP32)'}, ...
                                            'Position', [120, 550, 160, 22], ...
                                            'Callback', @(~,~) obj.handlePosModeChange());

            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Port:', ...
                      'Position', [10, 520, 35, 20], 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
            obj.PosPortEdit = uicontrol(ctrlPanel, 'Style', 'edit', 'String', 'COM9', ...
                                        'Position', [45, 520, 50, 22]);

            obj.PosConnectBtn = uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', 'Connect', ...
                                          'Position', [100, 520, 75, 24], ...
                                          'BackgroundColor', [0.2 0.6 0.2], 'ForegroundColor', 'w', ...
                                          'FontWeight', 'bold', ...
                                          'Callback', @(~,~) obj.togglePosConnect());

            obj.PosLamp = uicontrol(ctrlPanel, 'Style', 'text', 'String', 'OFFLINE', ...
                                    'Position', [180, 522, 75, 20], 'Enable', 'inactive', ...
                                    'BackgroundColor', [0.8 0.8 0.8], 'FontWeight', 'bold');

            obj.HomeBtn = uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', 'Zero Pan', ...
                                    'Position', [260, 520, 85, 24], ...
                                    'Callback', @(~,~) obj.homePositioner());

            % Divider line
            uicontrol(ctrlPanel, 'Style', 'text', 'String', repmat('-', 1, 55), ...
                      'Position', [10, 495, 340, 15], 'BackgroundColor', 'w');

            % 3. RF Frequency Parameters
            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Center Freq (MHz):', ...
                      'Position', [10, 470, 120, 20], 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
            obj.CenterFreqEdit = uicontrol(ctrlPanel, 'Style', 'edit', 'String', '2400.0', ...
                                           'Position', [140, 470, 80, 22]);

            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Span (MHz):', ...
                      'Position', [10, 440, 120, 20], 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
            obj.SpanEdit = uicontrol(ctrlPanel, 'Style', 'edit', 'String', '10.0', ...
                                     'Position', [140, 440, 80, 22]);

            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Points:', ...
                      'Position', [10, 410, 120, 20], 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
            obj.SweepPointsEdit = uicontrol(ctrlPanel, 'Style', 'edit', 'String', '11', ...
                                            'Position', [140, 410, 80, 22]);

            % 4. Angular Scan Parameters
            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Scan Axis:', ...
                      'Position', [10, 375, 120, 20], 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
            obj.AxisDropdown = uicontrol(ctrlPanel, 'Style', 'popupmenu', ...
                                         'String', {'Azimuth (AZ)', 'Elevation (EL)'}, ...
                                         'Position', [140, 375, 110, 22]);

            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Start → Stop (°):', ...
                      'Position', [10, 345, 120, 20], 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
            obj.StartAngleEdit = uicontrol(ctrlPanel, 'Style', 'edit', 'String', '0.0', ...
                                           'Position', [140, 345, 45, 22]);
            obj.StopAngleEdit  = uicontrol(ctrlPanel, 'Style', 'edit', 'String', '360.0', ...
                                           'Position', [190, 345, 45, 22]);

            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Angle Step (°):', ...
                      'Position', [10, 315, 120, 20], 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
            obj.StepAngleEdit = uicontrol(ctrlPanel, 'Style', 'edit', 'String', '2.0', ...
                                          'Position', [140, 315, 80, 22]);

            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Settle Time (s):', ...
                      'Position', [10, 285, 120, 20], 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
            obj.SettleTimeEdit = uicontrol(ctrlPanel, 'Style', 'edit', 'String', '0.2', ...
                                           'Position', [140, 285, 80, 22]);

            % 5. Start / Pause / Stop Buttons
            obj.StartScanBtn = uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', 'START SCAN', ...
                                         'Position', [10, 235, 155, 40], ...
                                         'BackgroundColor', [0.1 0.7 0.2], 'ForegroundColor', 'w', ...
                                         'FontSize', 11, 'FontWeight', 'bold', ...
                                         'Callback', @(~,~) obj.startScan());

            obj.PauseBtn = uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', 'Pause', ...
                                     'Position', [175, 235, 75, 40], ...
                                     'FontSize', 10, 'Enable', 'off', ...
                                     'Callback', @(~,~) obj.togglePause());

            obj.StopBtn = uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', 'STOP', ...
                                    'Position', [255, 235, 85, 40], ...
                                    'BackgroundColor', [0.8 0.2 0.2], 'ForegroundColor', 'w', ...
                                    'FontSize', 10, 'FontWeight', 'bold', 'Enable', 'off', ...
                                    'Callback', @(~,~) obj.abortScan());

            % 6. Metrics Display Card
            metricCard = uipanel(ctrlPanel, 'Title', 'Analysis Metrics', ...
                                 'FontWeight', 'bold', 'FontSize', 9, ...
                                 'Units', 'pixels', 'Position', [10, 80, 340, 145], ...
                                 'BackgroundColor', [0.96 0.98 1.0]);

            uicontrol(metricCard, 'Style', 'text', 'String', 'Main Beam Peak:', ...
                      'Position', [10, 100, 110, 18], 'HorizontalAlignment', 'left', 'BackgroundColor', [0.96 0.98 1.0]);
            obj.PeakAngleLabel = uicontrol(metricCard, 'Style', 'text', 'String', '--', ...
                                           'Position', [130, 100, 190, 18], 'HorizontalAlignment', 'left', ...
                                           'FontWeight', 'bold', 'BackgroundColor', [0.96 0.98 1.0]);

            uicontrol(metricCard, 'Style', 'text', 'String', 'HPBW (-3 dB):', ...
                      'Position', [10, 78, 110, 18], 'HorizontalAlignment', 'left', 'BackgroundColor', [0.96 0.98 1.0]);
            obj.HPBWLabel = uicontrol(metricCard, 'Style', 'text', 'String', '--', ...
                                      'Position', [130, 78, 190, 18], 'HorizontalAlignment', 'left', ...
                                      'FontWeight', 'bold', 'ForegroundColor', [0.8 0 0], 'BackgroundColor', [0.96 0.98 1.0]);

            uicontrol(metricCard, 'Style', 'text', 'String', 'Side-Lobe Level:', ...
                      'Position', [10, 56, 110, 18], 'HorizontalAlignment', 'left', 'BackgroundColor', [0.96 0.98 1.0]);
            obj.SLLLabel = uicontrol(metricCard, 'Style', 'text', 'String', '--', ...
                                     'Position', [130, 56, 190, 18], 'HorizontalAlignment', 'left', ...
                                     'FontWeight', 'bold', 'ForegroundColor', [0.6 0 0.6], 'BackgroundColor', [0.96 0.98 1.0]);

            uicontrol(metricCard, 'Style', 'text', 'String', 'Front-to-Back:', ...
                      'Position', [10, 34, 110, 18], 'HorizontalAlignment', 'left', 'BackgroundColor', [0.96 0.98 1.0]);
            obj.FBRLabel = uicontrol(metricCard, 'Style', 'text', 'String', '--', ...
                                     'Position', [130, 34, 190, 18], 'HorizontalAlignment', 'left', ...
                                     'FontWeight', 'bold', 'BackgroundColor', [0.96 0.98 1.0]);

            uicontrol(metricCard, 'Style', 'text', 'String', 'Max S21 Transmission:', ...
                      'Position', [10, 12, 120, 18], 'HorizontalAlignment', 'left', 'BackgroundColor', [0.96 0.98 1.0]);
            obj.PeakS21Label = uicontrol(metricCard, 'Style', 'text', 'String', '--', ...
                                         'Position', [130, 12, 190, 18], 'HorizontalAlignment', 'left', ...
                                         'FontWeight', 'bold', 'BackgroundColor', [0.96 0.98 1.0]);

            % 7. Export / Load Buttons
            uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', 'Export Dataset', ...
                      'Position', [10, 15, 100, 30], ...
                      'Callback', @(~,~) obj.exportCurrentData());

            uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', 'Load Scan File', ...
                      'Position', [120, 15, 100, 30], ...
                      'Callback', @(~,~) obj.loadDataset());

            % ── Right Tab Group (x=380, w=810) ───────────────────────────
            obj.TabGroup = uitabgroup(obj.Figure, 'Units', 'pixels', 'Position', [380, 65, 810, 705]);

            % Tab 1: Polar Pattern
            obj.PolarTab = uitab(obj.TabGroup, 'Title', '2D Polar Pattern');
            obj.PolarAx = polaraxes('Parent', obj.PolarTab, 'Units', 'normalized', 'Position', [0.08, 0.08, 0.84, 0.84]);
            title(obj.PolarAx, 'Radiation Pattern (2D Polar)', 'FontWeight', 'bold');
            obj.PolarAx.RLim = [-40, 0];
            obj.PolarAx.ThetaZeroLocation = 'top';
            obj.PolarAx.ThetaDir = 'clockwise';

            % Tab 2: Cartesian Pattern
            obj.CartTab = uitab(obj.TabGroup, 'Title', '2D Cartesian Pattern');
            obj.CartAx = axes('Parent', obj.CartTab, 'Units', 'normalized', 'Position', [0.10, 0.12, 0.84, 0.80]);
            title(obj.CartAx, 'Radiation Pattern (Cartesian: Angle vs Relative dB)', 'FontWeight', 'bold');
            xlabel(obj.CartAx, 'Angle (deg)');
            ylabel(obj.CartAx, 'Relative Transmission (dB)');
            grid(obj.CartAx, 'on');

            % Tab 3: Live RF S11 / S21 Frequency Monitor
            obj.RFMonitorTab = uitab(obj.TabGroup, 'Title', 'Live RF S11/S21 Monitor');
            obj.RFMonitorAx1 = subplot(2, 1, 1, 'Parent', obj.RFMonitorTab);
            title(obj.RFMonitorAx1, 'Forward Transmission |S21| across Sweep Band', 'FontWeight', 'bold');
            xlabel(obj.RFMonitorAx1, 'Frequency (MHz)'); ylabel(obj.RFMonitorAx1, '|S21| (dB)');
            grid(obj.RFMonitorAx1, 'on');

            obj.RFMonitorAx2 = subplot(2, 1, 2, 'Parent', obj.RFMonitorTab);
            title(obj.RFMonitorAx2, 'Input Reflection |S11| across Sweep Band', 'FontWeight', 'bold');
            xlabel(obj.RFMonitorAx2, 'Frequency (MHz)'); ylabel(obj.RFMonitorAx2, '|S11| (dB)');
            grid(obj.RFMonitorAx2, 'on');

            % Tab 4: 3D Pattern
            obj.ThreeDTab = uitab(obj.TabGroup, 'Title', '3D Spherical Pattern');
            obj.ThreeDAx = axes('Parent', obj.ThreeDTab, 'Units', 'normalized', 'Position', [0.10, 0.10, 0.80, 0.80]);
            title(obj.ThreeDAx, '3D Radiation Pattern', 'FontWeight', 'bold');

            % Tab 5: Dedicated System & Hardware Logs
            obj.LogTab = uitab(obj.TabGroup, 'Title', '📋 System & Hardware Logs');

            logToolbar = uipanel(obj.LogTab, 'Units', 'pixels', 'Position', [10, 10, 785, 45], ...
                                 'BackgroundColor', [0.95 0.96 0.98]);

            uicontrol(logToolbar, 'Style', 'pushbutton', 'String', '🗑️ Clear Log', ...
                      'Position', [10, 7, 95, 30], 'Callback', @(~,~) obj.clearLog());

            uicontrol(logToolbar, 'Style', 'pushbutton', 'String', '💾 Save Log (.txt)', ...
                      'Position', [115, 7, 125, 30], 'Callback', @(~,~) obj.saveLogToFile());

            uicontrol(logToolbar, 'Style', 'pushbutton', 'String', '📡 Query ESP32 Status', ...
                      'Position', [250, 7, 145, 30], 'Callback', @(~,~) obj.queryESP32Status());

            obj.LogCountLabel = uicontrol(logToolbar, 'Style', 'text', 'String', 'Log entries: 1', ...
                                          'Position', [405, 11, 370, 20], 'HorizontalAlignment', 'left', ...
                                          'FontWeight', 'bold', 'BackgroundColor', [0.95 0.96 0.98]);

            obj.LogConsoleBox = uicontrol(obj.LogTab, 'Style', 'listbox', ...
                                          'Units', 'pixels', 'Position', [10, 65, 785, 600], ...
                                          'FontName', 'Consolas', 'FontSize', 10, ...
                                          'BackgroundColor', [0.10 0.12 0.16], ...
                                          'ForegroundColor', [0.92 0.96 1.0], ...
                                          'String', {'[SYSTEM] Log console initialized. Ready.'});

            % ── Bottom Panel: Progress & Status Log (h=55) ───────────────
            uicontrol(obj.Figure, 'Style', 'text', 'String', 'Progress:', ...
                      'Position', [15, 36, 60, 20], 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
            obj.ProgressBar = uicontrol(obj.Figure, 'Style', 'edit', 'String', ' 0% [Ready]', ...
                                        'Position', [80, 37, 280, 22], 'Enable', 'inactive', ...
                                        'BackgroundColor', 'w', 'HorizontalAlignment', 'left');

            obj.StatusLabel = uicontrol(obj.Figure, 'Style', 'text', 'String', 'Status: Ready', ...
                                        'Position', [380, 36, 400, 20], 'HorizontalAlignment', 'left', 'FontWeight', 'bold');

            obj.LogListBox = uicontrol(obj.Figure, 'Style', 'listbox', ...
                                       'Position', [10, 5, 1180, 28], ...
                                       'String', {'[SYSTEM] Sẵn sàng. Nhấp sang tab "📋 System & Hardware Logs" để xem nhật ký toàn màn hình.'});
        end

        function handleStepProgress(obj, info)
            % Live real-time update on every step
            obj.LiveAngles(end+1) = info.CommandedAngle;
            obj.LiveS21_dB(end+1) = info.S21_dB_Center;

            norm_s21 = PatternAnalyzer.normalize(obj.LiveS21_dB);

            % Update Polar plot
            theta_rad = deg2rad(obj.LiveAngles);
            r = max(norm_s21, -40.0);
            cla(obj.PolarAx);
            hold(obj.PolarAx, 'on');
            polarplot(obj.PolarAx, theta_rad, r, 'b.-', 'LineWidth', 1.5, 'MarkerSize', 8);
            obj.PolarAx.RLim = [-40, 0];
            obj.PolarAx.ThetaZeroLocation = 'top';
            obj.PolarAx.ThetaDir = 'clockwise';
            title(obj.PolarAx, sprintf('Live Polar Pattern — Angle: %.1f° (%d/%d)', ...
                  info.CommandedAngle, info.Index, info.Total), 'FontWeight', 'bold');

            % Update Cartesian plot
            cla(obj.CartAx);
            hold(obj.CartAx, 'on');
            yline(obj.CartAx, -3.0, 'r--', 'LineWidth', 1.0);
            plot(obj.CartAx, obj.LiveAngles, norm_s21, 'b.-', 'LineWidth', 1.5, 'MarkerSize', 8);
            grid(obj.CartAx, 'on');
            title(obj.CartAx, sprintf('Live Cartesian Pattern — Step %d/%d', info.Index, info.Total), 'FontWeight', 'bold');
            xlabel(obj.CartAx, 'Angle (deg)');
            ylabel(obj.CartAx, 'Normalized Transmission (dB)');

            % Update Status and Progress
            obj.updateProgress(info.Progress * 100);
            if isfield(info, 'EncoderAngle') && ~isnan(info.EncoderAngle)
                obj.StatusLabel.String = sprintf('Status: Angle %.1f° (AS5600: %.1f°) | S21: %.2f dB | Elapsed: %.1f s', ...
                                                 info.CommandedAngle, info.EncoderAngle, info.S21_dB_Center, info.ElapsedSec);
            else
                obj.StatusLabel.String = sprintf('Status: Angle %.1f° | S21: %.2f dB | Elapsed: %.1f s', ...
                                                 info.CommandedAngle, info.S21_dB_Center, info.ElapsedSec);
            end
            drawnow limitrate;
        end

        function updateFinalResults(obj, scanData)
            % Update all metrics and plots after scan completion
            if isempty(scanData) || ~isstruct(scanData) || ~isfield(scanData, 'Analysis')
                return;
            end
            an = scanData.Analysis;

            if isfield(an, 'PeakAngle_deg') && ~isnan(an.PeakAngle_deg)
                obj.PeakAngleLabel.String = sprintf('%.2f°', an.PeakAngle_deg);
            else
                obj.PeakAngleLabel.String = '--';
            end

            if isfield(an, 'PeakVal_dB') && ~isnan(an.PeakVal_dB)
                obj.PeakS21Label.String = sprintf('%.2f dB', an.PeakVal_dB);
            else
                obj.PeakS21Label.String = '--';
            end

            if isfield(an, 'HPBW_deg') && ~isnan(an.HPBW_deg)
                obj.HPBWLabel.String = sprintf('%.2f° (%.1f° to %.1f°)', an.HPBW_deg, an.ThetaLeft_deg, an.ThetaRight_deg);
            else
                obj.HPBWLabel.String = 'N/A (No -3dB cut)';
            end

            if isfield(an, 'SLL_dB') && ~isnan(an.SLL_dB)
                obj.SLLLabel.String = sprintf('%.2f dB @ %.1f°', an.SLL_dB, an.SLLAngle_deg);
            else
                obj.SLLLabel.String = 'None detected';
            end

            if isfield(an, 'FBR_dB') && ~isnan(an.FBR_dB)
                obj.FBRLabel.String = sprintf('%.2f dB', an.FBR_dB);
            else
                obj.FBRLabel.String = 'N/A';
            end

            % Final Polar Plot with markers
            PatternAnalyzer.plotPolar(obj.PolarAx, scanData.Angles, scanData.NormalizedS21_dB, ...
                sprintf('Radiation Pattern — %.3f MHz', scanData.SelectedFreqHz/1e6));

            % Final Cartesian Plot with markers
            PatternAnalyzer.plotCartesian(obj.CartAx, scanData.Angles, scanData.NormalizedS21_dB, ...
                sprintf('Cartesian Pattern (HPBW: %.1f°, SLL: %.1f dB)', an.HPBW_deg, an.SLL_dB));

            % Plot RF sweep monitor at peak angle
            if isfield(scanData, 'SelectedS21_dB') && ~isempty(scanData.SelectedS21_dB) && size(scanData.S21, 1) > 0
                [~, peak_idx] = max(scanData.SelectedS21_dB);
                freq_mhz = scanData.FrequenciesHz / 1e6;
                cla(obj.RFMonitorAx1);
                plot(obj.RFMonitorAx1, freq_mhz, 20*log10(abs(scanData.S21(peak_idx, :))), 'b-o', 'LineWidth', 1.5);
                grid(obj.RFMonitorAx1, 'on');
                title(obj.RFMonitorAx1, sprintf('|S21| Trace across Band at Peak Angle (%.1f°)', scanData.Angles(peak_idx)));
                xlabel(obj.RFMonitorAx1, 'Frequency (MHz)'); ylabel(obj.RFMonitorAx1, 'S21 (dB)');

                cla(obj.RFMonitorAx2);
                plot(obj.RFMonitorAx2, freq_mhz, 20*log10(abs(scanData.S11(peak_idx, :))), 'r-o', 'LineWidth', 1.5);
                grid(obj.RFMonitorAx2, 'on');
                title(obj.RFMonitorAx2, sprintf('|S11| Return Loss at Peak Angle (%.1f°)', scanData.Angles(peak_idx)));
                xlabel(obj.RFMonitorAx2, 'Frequency (MHz)'); ylabel(obj.RFMonitorAx2, 'S11 (dB)');
            end

            % 3D Surface (requires at least 3 points)
            if length(scanData.Angles) >= 3
                obj.plot3DSurface(scanData.Angles, scanData.NormalizedS21_dB);
            end
            drawnow;
        end

        function plot3DSurface(obj, angles_deg, s21_rel_db)
            % Plot 3D Toroidal/Spherical radiation pattern
            cla(obj.ThreeDAx);
            if length(angles_deg) < 3 || isempty(s21_rel_db)
                return;
            end
            phi = deg2rad(angles_deg);
            theta = deg2rad(linspace(-90, 90, 30));
            [THETA, PHI] = meshgrid(theta, phi);

            % Approximate elevation rolloff cos(theta)
            r_db = repmat(s21_rel_db(:), 1, length(theta)) + 20*log10(max(cos(THETA), 0.05));
            r_db = max(r_db, -35.0);
            R = r_db - min(r_db(:)) + 5.0; % Positive radius for 3D sphere

            [X, Y, Z] = sph2cart(PHI, THETA, R);
            surf(obj.ThreeDAx, X, Y, Z, r_db, 'EdgeColor', 'none');
            axis(obj.ThreeDAx, 'equal'); grid(obj.ThreeDAx, 'on');
            view(obj.ThreeDAx, 45, 30);
            colormap(obj.ThreeDAx, 'jet');
            cb = colorbar(obj.ThreeDAx);
            cb.Label.String = 'Relative S21 (dB)';
            title(obj.ThreeDAx, '3D Radiation Pattern Model', 'FontWeight', 'bold');
        end

        function handleVNAModeChange(obj)
            val = obj.VNAModeDropdown.Value;
            if val == 1
                obj.VNA = VNAController('Mode', 'Mock');
                obj.Orchestrator.VNA = obj.VNA;
                obj.log('VNA switched to Mock mode.');
            else
                obj.VNA = VNAController('Mode', 'Real');
                obj.Orchestrator.VNA = obj.VNA;
                obj.log('VNA switched to Real hardware mode.');
            end
            obj.updateConnectionStatus();
        end

        function handlePosModeChange(obj)
            val = obj.PosModeDropdown.Value;
            port = strtrim(obj.PosPortEdit.String);
            if isempty(port), port = 'COM9'; end
            if val == 1
                obj.Positioner = PositionerController('Mode', 'Mock');
                obj.Orchestrator.Positioner = obj.Positioner;
                obj.log('Positioner switched to Mock mode.');
            else
                obj.Positioner = PositionerController('Mode', 'Hardware', 'Port', port, 'TiltDisabled', true);
                obj.Orchestrator.Positioner = obj.Positioner;
                obj.log(sprintf('Positioner switched to Hardware (ESP32 on %s) [Khóa an toàn Tilt: BẬT].', port));
            end
            obj.updateConnectionStatus();
        end

        function toggleVNAConnect(obj)
            if obj.VNA.IsConnected
                obj.VNA.disconnect();
                obj.log('VNA disconnected.');
            else
                port = strtrim(obj.VNAPortEdit.String);
                try
                    obj.VNA.connect(port);
                    obj.log(sprintf('Connected to VNA on %s (Variant: 0x%02X)', port, obj.VNA.DeviceIdentity.device_variant));
                catch ME
                    errordlg(sprintf('VNA connect error: %s', ME.message), 'Connection Error');
                    obj.log(sprintf('❌ VNA connect error: %s', ME.message));
                    if ~isempty(obj.LogTab) && isvalid(obj.LogTab)
                        obj.TabGroup.SelectedTab = obj.LogTab;
                    end
                end
            end
            obj.updateConnectionStatus();
        end

        function togglePosConnect(obj)
            if obj.Positioner.IsConnected
                obj.Positioner.disconnect();
                obj.log('Positioner đã ngắt kết nối.');
            else
                port = strtrim(obj.PosPortEdit.String);
                if isempty(port), port = 'COM9'; end
                try
                    obj.Positioner.connect(port);
                    obj.log(sprintf('✓ Đã kết nối Positioner trên %s (Góc AS5600: %.1f°, Khóa Tilt: %d).', ...
                            port, obj.Positioner.AzimuthEncoderDeg, obj.Positioner.TiltDisabled));
                catch ME
                    errordlg(sprintf('Positioner connect error: %s', ME.message), 'Connection Error');
                    obj.log(sprintf('❌ Lỗi kết nối Positioner trên %s: %s', port, ME.message));
                    if ~isempty(obj.LogTab) && isvalid(obj.LogTab)
                        obj.TabGroup.SelectedTab = obj.LogTab;
                    end
                end
            end
            obj.updateConnectionStatus();
        end

        function homePositioner(obj)
            try
                % Auto-connect if not connected yet
                if ~obj.Positioner.IsConnected
                    port = strtrim(obj.PosPortEdit.String);
                    if isempty(port), port = 'COM9'; end
                    obj.log(sprintf('⚠️ Positioner chưa kết nối! Đang tự động kết nối tới %s...', port));
                    obj.Positioner.connect(port);
                    obj.updateConnectionStatus();
                end

                obj.Positioner.home('AZ');
                obj.log(sprintf('✓ Đã ghim vị trí Pan thành công (ZERO 0.00°). Góc AS5600: %.1f°', ...
                        obj.Positioner.AzimuthEncoderDeg));
            catch ME
                obj.log(sprintf('❌ Lỗi Homing / Zero: %s', ME.message));
                errordlg(sprintf('Lỗi Homing / Zero: %s', ME.message), 'Homing Error');
                if ~isempty(obj.LogTab) && isvalid(obj.LogTab)
                    obj.TabGroup.SelectedTab = obj.LogTab;
                end
            end
        end

        function updateConnectionStatus(obj)
            if obj.VNA.IsConnected
                obj.VNALamp.String = 'ONLINE';
                obj.VNALamp.BackgroundColor = [0.4 0.9 0.4];
                obj.VNAConnectBtn.String = 'Disconnect';
                obj.VNAConnectBtn.BackgroundColor = [0.8 0.3 0.3];
            else
                obj.VNALamp.String = 'OFFLINE';
                obj.VNALamp.BackgroundColor = [0.8 0.8 0.8];
                obj.VNAConnectBtn.String = 'Connect';
                obj.VNAConnectBtn.BackgroundColor = [0.2 0.6 0.2];
            end

            if ~isempty(obj.PosLamp) && isvalid(obj.PosLamp)
                if obj.Positioner.IsConnected
                    obj.PosLamp.String = 'ONLINE';
                    obj.PosLamp.BackgroundColor = [0.4 0.9 0.4];
                    obj.PosConnectBtn.String = 'Disconnect';
                    obj.PosConnectBtn.BackgroundColor = [0.8 0.3 0.3];
                else
                    obj.PosLamp.String = 'OFFLINE';
                    obj.PosLamp.BackgroundColor = [0.8 0.8 0.8];
                    obj.PosConnectBtn.String = 'Connect';
                    obj.PosConnectBtn.BackgroundColor = [0.2 0.6 0.2];
                end
            end
        end

        function updateProgress(obj, pct)
            bars = repmat('=', 1, round(pct / 5));
            spaces = repmat(' ', 1, 20 - round(pct / 5));
            obj.ProgressBar.String = sprintf(' %3d%% [%s%s]', pct, bars, spaces);
        end

        function log(obj, msg)
            timestamp = char(datetime('now', 'Format', 'HH:mm:ss'));
            new_entry = sprintf('[%s] %s', timestamp, msg);

            % Update dedicated Log Tab console
            if ~isempty(obj.LogConsoleBox) && isvalid(obj.LogConsoleBox)
                cur = obj.LogConsoleBox.String;
                if ischar(cur), cur = {cur}; end
                cur{end+1, 1} = new_entry;
                obj.LogConsoleBox.String = cur;
                obj.LogConsoleBox.Value = length(cur);
                if ~isempty(obj.LogCountLabel) && isvalid(obj.LogCountLabel)
                    obj.LogCountLabel.String = sprintf('Log entries: %d | Last update: %s', length(cur), timestamp);
                end
            end

            % Update bottom status log bar
            if ~isempty(obj.LogListBox) && isvalid(obj.LogListBox)
                current_log = obj.LogListBox.String;
                if ischar(current_log), current_log = {current_log}; end
                obj.LogListBox.String = [current_log; {new_entry}];
                obj.LogListBox.Value = length(obj.LogListBox.String);
            end

            % Print to MATLAB Command Window
            fprintf('%s\n', new_entry);
        end

        function clearLog(obj)
            timestamp = char(datetime('now', 'Format', 'HH:mm:ss'));
            initial_msg = sprintf('[%s] [SYSTEM] Log cleared by user.', timestamp);
            if ~isempty(obj.LogConsoleBox) && isvalid(obj.LogConsoleBox)
                obj.LogConsoleBox.String = {initial_msg};
                obj.LogConsoleBox.Value = 1;
                if ~isempty(obj.LogCountLabel) && isvalid(obj.LogCountLabel)
                    obj.LogCountLabel.String = 'Log entries: 1';
                end
            end
            if ~isempty(obj.LogListBox) && isvalid(obj.LogListBox)
                obj.LogListBox.String = {initial_msg};
                obj.LogListBox.Value = 1;
            end
        end

        function saveLogToFile(obj)
            matlab_dir = fileparts(fileparts(mfilename('fullpath')));
            projects_dir = fileparts(matlab_dir);
            log_dir = fullfile(projects_dir, 'data', 'logs');
            if ~exist(log_dir, 'dir')
                mkdir(log_dir);
            end
            fname = sprintf('system_log_%s.txt', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
            filepath = fullfile(log_dir, fname);
            fid = fopen(filepath, 'w', 'n', 'UTF-8');
            if fid ~= -1
                for k = 1:length(obj.LogConsoleBox.String)
                    fprintf(fid, '%s\r\n', obj.LogConsoleBox.String{k});
                end
                fclose(fid);
                obj.log(sprintf('✓ Đã lưu file log thành công: %s', filepath));
                msgbox(sprintf('Đã lưu file log thành công vào:\n%s', filepath), 'Save Log');
            else
                obj.log('❌ Không thể tạo file để lưu log!');
            end
        end

        function queryESP32Status(obj)
            if ~obj.Positioner.IsConnected
                obj.log('⚠️ ESP32 chưa kết nối! Đang tự động kết nối...');
                obj.togglePosConnect();
            end
            if obj.Positioner.IsConnected
                pan = obj.Positioner.getPosition('AZ');
                encPan = obj.Positioner.getEncoderPosition('AZ');
                tilt = obj.Positioner.getPosition('EL');
                encTilt = obj.Positioner.getEncoderPosition('EL');
                obj.log(sprintf('📡 [ESP32 STATUS] Pan = %.2f° (AS5600 J4: %.2f°) | Tilt = %.2f° (AS5600 J3: %.2f°) | Khóa Tilt: %d', ...
                        pan, encPan, tilt, encTilt, obj.Positioner.TiltDisabled));
            end
        end
    end
end
