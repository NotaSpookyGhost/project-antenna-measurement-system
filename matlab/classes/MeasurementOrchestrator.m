classdef MeasurementOrchestrator < handle
    % MEASUREMENTORCHESTRATOR Synchronized Scan Engine for Antenna Measurement System.
    %
    % Manages the automated measurement state machine per Master Doc §10.1, §19:
    %   1. Positioner commands target angle
    %   2. Motor moves, AS5600 confirms position feedback
    %   3. Mechanical settling delay
    %   4. VNA sweeps and returns fresh complex S11/S21
    %   5. Data logging and real-time polar/Cartesian update
    %   6. Advance to next angle or finish scan
    %
    % Supports:
    %   - 2D Azimuth scans (0 to 360 deg or sector scans)
    %   - Real VNA + Mock Positioner (ideal for current hardware stage)
    %   - Full Mock mode or Full Real Hardware mode
    %   - Real-time callbacks for GUI / CLI progress
    %   - Pause / Resume / Cancel safety controls

    properties
        VNA VNAController
        Positioner PositionerController

        % Scan configuration
        StartAngleDeg double = 0.0
        StopAngleDeg double = 360.0
        StepAngleDeg double = 2.0
        Axis char = 'AZ'                   % 'AZ' or 'EL'
        Scan3DConfig struct = ScanGeometry.defaults()
        AcquisitionMode char = 'Stepwise'

        CenterFreqHz double = 2.4e9
        SpanHz double = 10e6
        SweepPoints int32 = 11

        SettleTimeSec double = 0.25

        % Callbacks for real-time visualization
        StepCallback function_handle = function_handle.empty
        StatusCallback function_handle = function_handle.empty
    end

    properties (SetAccess = private)
        State char = 'IDLE'                % 'IDLE','HOMING','SCANNING','PAUSED','COMPLETED','ABORTED'
        IsRunning logical = false
        IsPaused logical = false
        CurrentIndex int32 = 0
        TotalSteps int32 = 0
        Progress double = 0.0

        LastScanData struct = struct()
    end

    properties (Access = private)
        CancelRequested logical = false
    end

    events
        ScanStarted
        StepProgress
        ScanCompleted
        ScanAborted
    end

    methods
        function obj = MeasurementOrchestrator(vna, positioner)
            % MEASUREMENTORCHESTRATOR Constructor
            if nargin >= 1 && ~isempty(vna)
                obj.VNA = vna;
            else
                obj.VNA = VNAController('Mode', 'Mock');
            end

            if nargin >= 2 && ~isempty(positioner)
                obj.Positioner = positioner;
            else
                obj.Positioner = PositionerController('Mode', 'Mock');
            end
        end

        function setScanParameters(obj, startAng, stopAng, stepAng, centerHz, spanHz, points)
            % SETSCANPARAMETERS Configure angular and frequency sweep
            obj.StartAngleDeg = double(startAng);
            obj.StopAngleDeg  = double(stopAng);
            obj.StepAngleDeg  = double(stepAng);

            if nargin >= 5 && ~isempty(centerHz), obj.CenterFreqHz = double(centerHz); end
            if nargin >= 6 && ~isempty(spanHz),   obj.SpanHz = double(spanHz); end
            if nargin >= 7 && ~isempty(points),   obj.SweepPoints = int32(points); end
        end

        function scanData = startScan(obj)
            % STARTSCAN Execute the automated scan sequence
            if strcmpi(obj.AcquisitionMode,'Continuous')
                if strcmpi(obj.Axis,'PAN'), obj.Axis='AZ'; end
                if strcmpi(obj.Axis,'TILT'), obj.Axis='EL'; end
            end
            if strcmpi(obj.Axis,'3D')
                scanData = obj.startScan3D();
                return;
            end
            if obj.IsRunning
                error('MeasurementOrchestrator:AlreadyRunning', 'A scan is already in progress.');
            end
            continuous=strcmp(validatestring(obj.AcquisitionMode,{'Stepwise','Continuous'}),'Continuous');
            if continuous && ~ismember(obj.VNA.Mode,{'ShockLine','Mock'})
                error('MeasurementOrchestrator:ContinuousMode','Continuous acquisition requires ShockLine.');
            end

            % Calculate angles (Start > Stop => CCW / descending)
            angles = MeasurementOrchestrator.buildAngleVector( ...
                obj.StartAngleDeg, obj.StopAngleDeg, obj.StepAngleDeg);
            requestedAngles=angles;

            obj.TotalSteps = int32(length(angles));
            obj.CurrentIndex = 0;
            obj.Progress = 0.0;
            obj.CancelRequested = false;
            obj.IsPaused = false;
            obj.IsRunning = true;
            guard = onCleanup(@() obj.resetRunning());
            obj.setState('INITIALIZING');

            obj.logStatus(sprintf('Starting scan: %.1f° to %.1f° (step %.2f°, %d points)', ...
                          obj.StartAngleDeg, obj.StopAngleDeg, obj.StepAngleDeg, obj.TotalSteps));

            % 1. Ensure connections
            if ~obj.Positioner.IsConnected
                obj.Positioner.connect();
            end
            if obj.Positioner.ManualHomingActive
                error('MeasurementOrchestrator:ManualHomingRequired', ...
                    'Motor is released for manual homing. Lock and ZERO both axes before scanning.');
            end
            if obj.Positioner.HoldingSupported && ~obj.Positioner.HoldingActive
                error('MeasurementOrchestrator:HoldLost', ...
                    'Holding torque is unavailable. Reconnect and calibrate before scanning.');
            end
            % Reject the complete range before any RF setup or motor movement.
            obj.Positioner.validateTargets(obj.Axis,angles);
            if ~obj.VNA.IsConnected
                obj.VNA.connect();
            end

            % Configure VNA sweep once
            start_freq = obj.CenterFreqHz - obj.SpanHz / 2;
            stop_freq  = obj.CenterFreqHz + obj.SpanHz / 2;
            obj.VNA.configureSweep(start_freq, stop_freq, obj.SweepPoints);

            % Check Tilt safety lock
            if (strcmpi(obj.Axis, 'EL') || strcmpi(obj.Axis, 'TILT')) && obj.Positioner.TiltDisabled
                error('MeasurementOrchestrator:TiltDisabled', ...
                      'Trục Tilt đang bị khóa bảo vệ vì phản hồi AS5600 chưa đạt. Vui lòng chọn quét trục Azimuth (Pan)!');
            end

            % ZERO defines a physical reference; never redefine it at scan start.
            if ~obj.Positioner.IsHomed
                error('MeasurementOrchestrator:ManualHomingRequired', ...
                    'Chưa có mốc ZERO hợp lệ. Căn hai trục rồi bấm Khóa + ZERO trước khi quét.');
            end
            [~, initialEncoder] = obj.Positioner.getPositionSnapshot(obj.Axis, true);
            if continuous
                obj.readBothAxes();
                if (strcmpi(obj.Axis,'EL') && ~obj.Positioner.ContinuousTiltSupported) || ...
                        (~strcmpi(obj.Axis,'EL') && ~obj.Positioner.ContinuousPanSupported)
                    error('PositionerController:ContinuousUnsupported','Upload continuous-axis firmware before scanning.');
                end
                obj.Positioner.validateTargets(obj.Axis,angles);
            end
            if ~isfinite(initialEncoder) || initialEncoder < 0
                obj.setState('ABORTED');
                error('MeasurementOrchestrator:EncoderUnavailable', ...
                    'AS5600 chưa có phản hồi hợp lệ. Không bắt đầu quét; motor vẫn giữ.');
            end
            obj.logStatus('Giữ nguyên mốc ZERO; quay tới góc bắt đầu theo mốc đã đặt.');
            if obj.CancelRequested
                obj.setState('ABORTED');
                obj.logStatus('Scan dừng trong bước homing, chưa đo điểm mới.');
                notify(obj, 'ScanAborted');
                scanData = [];
                return;
            end

            % 3. Pre-allocate storage matrices
            N_angles = length(angles);
            N_freqs = double(obj.SweepPoints);

            s11_matrix = complex(zeros(N_angles, N_freqs));
            s21_matrix = complex(zeros(N_angles, N_freqs));
            measured_angles = zeros(1, N_angles);
            encoder_angles = zeros(1, N_angles);
            sweepStartAngle=nan(1,N_angles); sweepEndAngle=sweepStartAngle;
            sweepStartTime=sweepStartAngle; sweepEndTime=sweepStartAngle;
            frequencies_hz = linspace(start_freq, stop_freq, N_freqs);
            committedInstrumentMetadata=struct();

            obj.setState('SCANNING');
            notify(obj, 'ScanStarted');
            scan_tic = tic;

            % 4. Main Synchronized Scan Loop
            nDone = 0;
            aborted = false;
            abortReason = '';
            resolutionLimited=false;
            try
                for i = 1:N_angles
                    drawnow limitrate;   % let STOP / Pause callbacks run
                    if obj.CancelRequested
                        aborted = true;
                        break;
                    end

                    % Handle Pause
                    while obj.IsPaused
                        pause(0.1);
                        if obj.CancelRequested, break; end
                    end
                    if obj.CancelRequested
                        aborted = true;
                        break;
                    end

                    target_th = requestedAngles(i);
                    atEndBefore=false;
                    obj.CurrentIndex = int32(i);
                    obj.Progress = double(i) / double(N_angles);

                    % Step A: Move Positioner
                    if continuous && i>1
                        direction=sign(obj.StopAngleDeg-obj.StartAngleDeg);
                        pose=obj.Positioner.pollContinuousPan();
                        actual=obj.axisPoseAngle(pose);
                        target_th=obj.continuousSampleTarget(actual,target_th,obj.StartAngleDeg,obj.StopAngleDeg,obj.StepAngleDeg);
                        while direction*(actual-target_th)<0 && obj.Positioner.IsMoving
                            drawnow limitrate;
                            if obj.CancelRequested, break; end
                            pause(0.01); pose=obj.Positioner.pollContinuousPan(); actual=obj.axisPoseAngle(pose);
                        end
                        angles(i)=target_th;
                        atEndBefore=~obj.Positioner.IsMoving;
                        obj.Progress=min(1,abs((actual-obj.StartAngleDeg)/(obj.StopAngleDeg-obj.StartAngleDeg)));
                    else
                        obj.Positioner.moveTo(obj.Axis, target_th);
                    end
                    if obj.CancelRequested
                        aborted = true;
                        break;
                    end

                    % Logical output angle and motor-shaft telemetry from one snapshot.
                    if continuous && i>1
                        actual_th=obj.axisPoseAngle(pose);
                        actual_enc=pose.PanEncoderDeg;
                        if strcmpi(obj.Axis,'EL'), actual_enc=pose.TiltEncoderDeg; end
                    else
                        [actual_th, actual_enc] = obj.Positioner.getPositionSnapshot(obj.Axis, false);
                    end
                    if ~isfinite(actual_enc) || actual_enc < 0
                        aborted = true;
                        abortReason = 'EncoderUnavailable';
                        obj.logStatus('AS5600 mất tín hiệu: dừng quét trước khi đo điểm mới. Motor vẫn giữ; dữ liệu đã đo được giữ lại.');
                        break;
                    end
                    measured_angles(i) = actual_th;
                    encoder_angles(i) = actual_enc;

                    % Update mock VNA target angle if running in mock mode
                    if strcmpi(obj.VNA.Mode, 'Mock')
                        obj.VNA.setMockAngle(actual_th);
                    end

                    % Step C: Mechanical Settle Delay
                    if obj.SettleTimeSec > 0 && (~continuous || i==1)
                        pause(obj.SettleTimeSec);
                    end
                    if obj.CancelRequested
                        aborted = true;
                        break;
                    end

                    % Step D: Acquire fresh sweep from VNA
                    sweepStartAngle(i)=actual_th; sweepStartTime(i)=toc(scan_tic);
                    if continuous && i>1
                        sweep=obj.VNA.acquireMovingSweep(@()obj.continuousPose(scan_tic));
                        sweepStartAngle(i)=obj.axisPoseAngle(sweep.MotionBefore);
                        sweepEndAngle(i)=obj.axisPoseAngle(sweep.MotionAfter);
                        sweepStartTime(i)=sweep.MotionBefore.ElapsedSec;
                        sweepEndTime(i)=sweep.MotionAfter.ElapsedSec;
                        measured_angles(i)=(sweepStartAngle(i)+sweepEndAngle(i))/2;
                        span=abs(sweepEndAngle(i)-sweepStartAngle(i));
                        span=max(span,abs(measured_angles(i)-measured_angles(i-1)));
                        resolutionLimited=obj.reportContinuousSpacing(resolutionLimited,span,obj.StepAngleDeg);
                        actual_th=measured_angles(i);
                        encoder_angles(i)=sweep.MotionAfter.PanEncoderDeg;
                        if strcmpi(obj.Axis,'EL'), encoder_angles(i)=sweep.MotionAfter.TiltEncoderDeg; end
                        actual_enc=encoder_angles(i);
                        if i==N_angles || atEndBefore, obj.Positioner.endContinuousPan(false); end
                    else
                        sweep=obj.VNA.acquireSingle();
                        sweepEndAngle(i)=actual_th; sweepEndTime(i)=toc(scan_tic);
                    end

                    if obj.CancelRequested, aborted=true; break; end
                    if numel(sweep.FrequencyHz)~=N_freqs || numel(sweep.S11)~=N_freqs || ...
                            numel(sweep.S21)~=N_freqs || any(~isfinite(sweep.FrequencyHz)) || ...
                            any(diff(sweep.FrequencyHz)<=0) || any(~isfinite(sweep.S11)) || any(~isfinite(sweep.S21))
                        error('MeasurementOrchestrator:InvalidSweep','Incomplete or invalid VNA sweep.');
                    end
                    actualGrid=reshape(sweep.FrequencyHz,1,[]);
                    if nDone>0 && ~isequal(actualGrid,frequencies_hz)
                        error('MeasurementOrchestrator:InvalidSweep','VNA frequency grid changed during scan.');
                    end
                    nextMetadata=MeasurementOrchestrator.validateInstrumentProvenance(sweep,committedInstrumentMetadata);
                    frequencies_hz=actualGrid;
                    committedInstrumentMetadata=nextMetadata;

                    % Step E: Store instrument complex records
                    s11_matrix(i, :) = sweep.S11;
                    s21_matrix(i, :) = sweep.S21;
                    nDone = i;

                    % Find center frequency index for real-time visualization
                    [~, center_idx] = min(abs(frequencies_hz - obj.CenterFreqHz));
                    center_s21_db = sweep.S21_dB(center_idx);

                    % Step F: Trigger progress callback
                    if ~isempty(obj.StepCallback)
                        stepInfo = struct(...
                            'Index', i, ...
                            'Total', N_angles, ...
                            'CommandedAngle', target_th, ...
                            'MeasuredAngle', actual_th, ...
                            'EncoderAngle', actual_enc, ...
                            'S21_dB_Center', center_s21_db, ...
                            'Progress', obj.Progress, ...
                            'ElapsedSec', toc(scan_tic));
                        obj.StepCallback(stepInfo);
                    end

                    notify(obj, 'StepProgress');
                    if continuous && i==1 && ~obj.CancelRequested
                        obj.Positioner.beginContinuousAxis(obj.Axis,obj.StopAngleDeg);
                    end
                    if continuous && atEndBefore, break; end
                end
            catch ME
                if strcmp(ME.identifier, 'PositionerController:EncoderUnavailable')
                    aborted = true;
                    abortReason = 'EncoderUnavailable';
                    obj.logStatus('AS5600 mất tín hiệu: dừng quét, giữ motor và các điểm đã đo.');
                elseif obj.CancelRequested && strcmp(ME.identifier, 'PositionerController:Aborted')
                    % STOP interrupts serial waits; process the completed rows below.
                    aborted = true;
                elseif strcmpi(obj.VNA.Mode,'ShockLine') || continuous
                    aborted=true; abortReason=ME.identifier;
                    obj.logStatus(['VNA scan stopped: ' ME.message]);
                else
                    rethrow(ME);
                end
            end
            if continuous
                try
                    obj.Positioner.endContinuousPan();
                catch ME
                    aborted=true; abortReason=ME.identifier;
                    obj.logStatus(['Continuous motion cleanup: ' ME.message]);
                end
            end
            if obj.CancelRequested
                aborted=true;
                if isempty(abortReason), abortReason='UserStop'; end
            end

            total_time_sec = toc(scan_tic);

            % Trim to the points actually measured (abort support)
            if nDone < N_angles
                keep = 1:nDone;
                angles = angles(keep);
                s11_matrix = s11_matrix(keep, :);
                s21_matrix = s21_matrix(keep, :);
                measured_angles = measured_angles(keep);
                encoder_angles = encoder_angles(keep);
            end

            if aborted && (nDone==0 || (nDone<2 && ~strcmpi(obj.VNA.Mode,'ShockLine')))
                obj.setState('ABORTED');
                obj.logStatus('Scan dừng, chưa đủ dữ liệu (cần >= 2 điểm).');
                notify(obj, 'ScanAborted');
                scanData = [];
                return;
            end

            obj.setState('PROCESSING');
            obj.logStatus(sprintf('Scan loop finished (%d/%d points, %.2f s). Processing data...', ...
                          nDone, N_angles, total_time_sec));

            % 5. Post-Process Scan Data
            [~, center_freq_idx] = min(abs(frequencies_hz - obj.CenterFreqHz));
            s21_center_raw_db = 20 * log10(max(abs(s21_matrix(:, center_freq_idx)), 1e-12))';
            s21_center_phase = rad2deg(angle(s21_matrix(:, center_freq_idx)))';
            s21_normalized_db = PatternAnalyzer.normalize(s21_center_raw_db);

            peak_angle = NaN; peak_val = NaN; hpbw = NaN; th_left = NaN; th_right = NaN;
            analysisAngles=angles; if continuous, analysisAngles=measured_angles; end
            sll = NaN; sll_angle = NaN; fbr = NaN;
            try
                if nDone>=2
                [peak_angle, peak_val] = PatternAnalyzer.findMainLobe(analysisAngles, s21_center_raw_db);
                [hpbw, th_left, th_right] = PatternAnalyzer.calculateHPBW(analysisAngles, s21_normalized_db);
                [sll, sll_angle] = PatternAnalyzer.calculateSLL(analysisAngles, s21_normalized_db, hpbw);
                fbr = PatternAnalyzer.calculateFBR(analysisAngles, s21_normalized_db);
                end
            catch MEa
                obj.logStatus(sprintf('Cảnh báo phân tích búp sóng: %s', MEa.message));
            end

            analysis = struct(...
                'PeakAngle_deg', peak_angle, ...
                'PeakVal_dB', peak_val, ...
                'HPBW_deg', hpbw, ...
                'ThetaLeft_deg', th_left, ...
                'ThetaRight_deg', th_right, ...
                'SLL_dB', sll, ...
                'SLLAngle_deg', sll_angle, ...
                'FBR_dB', fbr);

            % On the installed pan wiring, increasing angles turn CCW viewed from above.
            if obj.StopAngleDeg >= obj.StartAngleDeg
                dirStr = 'CCW';
            else
                dirStr = 'CW';
            end

            metadata = struct(...
                'Device', obj.VNA.deviceName(), ...
                'VNAIdentity',obj.VNA.DeviceIdentity, ...
                'InstrumentMetadata',committedInstrumentMetadata, ...
                'VNAPort', obj.VNA.Port, ...
                'VNAMode', obj.VNA.Mode, ...
                'PositionerMode', obj.Positioner.Mode, ...
                'PositionerPort', obj.Positioner.Port, ...
                'AngleSource', 'Commanded step count; not independently measured antenna angle', ...
                'EncoderLocation', 'Motor shaft, modulo 360 deg; reduction 90/16', ...
                'EncoderAvailableAllPoints', all(isfinite(encoder_angles)), ...
                'ScanAxis', obj.Axis, ...
                'ScanDirection', dirStr, ...
                'StartAngleDeg', obj.StartAngleDeg, ...
                'StopAngleDeg', obj.StopAngleDeg, ...
                'AngleStepDeg', obj.StepAngleDeg, ...
                'TotalAngles', N_angles, ...
                'CompletedPoints', nDone, ...
                'Aborted', aborted, ...
                'AbortReason', abortReason, ...
                'CenterFreqHz', obj.CenterFreqHz, ...
                'SpanHz', obj.SpanHz, ...
                'SweepPoints', obj.SweepPoints, ...
                'SettleTimeSec', obj.SettleTimeSec, ...
                'TotalTimeSec', total_time_sec, ...
                'Firmware', 'See VNAIdentity for instrument firmware/version', ...
                'Timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));

            scanData = struct(...
                'Metadata', metadata, ...
                'Angles', angles, ...
                'MeasuredAngles', measured_angles, ...
                'EncoderAngles', encoder_angles, ...
                'EncoderValid', isfinite(encoder_angles), ...
                'FrequenciesHz', frequencies_hz, ...
                'SelectedFreqHz', obj.CenterFreqHz, ...
                'S11', s11_matrix, ...
                'S21', s21_matrix, ...
                'SelectedS21_dB', s21_center_raw_db, ...
                'SelectedS21_PhaseDeg', s21_center_phase, ...
                'NormalizedS21_dB', s21_normalized_db, ...
                'Analysis', analysis);
            if continuous
                scanData.Metadata.AcquisitionMode='Continuous';
                scanData.Metadata.ResolutionLimited=resolutionLimited;
                scanData.Metadata.RequestedTotalAngles=N_angles;
                scanData.Metadata.MaxMeasuredGapDeg=max([0 abs(diff(measured_angles))]);
                scanData.Metadata.MaxSweepAngularSpanDeg=max(abs(sweepEndAngle(1:nDone)-sweepStartAngle(1:nDone)));
                scanData.Metadata.MotionStopConfirmed=~obj.Positioner.IsMoving;
                scanData.Metadata.AngleSource='Moving-axis encoder sweep midpoint relative to scan start';
                scanData.CommandedAngles=angles;
                scanData.Angles=measured_angles;
                scanData.SweepStartAngleDeg=sweepStartAngle(1:nDone);
                scanData.SweepEndAngleDeg=sweepEndAngle(1:nDone);
                scanData.SweepStartSec=sweepStartTime(1:nDone);
                scanData.SweepEndSec=sweepEndTime(1:nDone);
            end

            obj.LastScanData = scanData;
            if aborted
                obj.setState('ABORTED');
                obj.logStatus(sprintf('Scan đã dừng ở %d/%d điểm, dữ liệu một phần được giữ lại.', nDone, N_angles));
                notify(obj, 'ScanAborted');
            else
                obj.setState('COMPLETED');
                obj.Progress=1;
                obj.logStatus(sprintf('Scan successfully completed! HPBW = %.2f°, SLL = %.2f dB, Peak = %.2f°', ...
                              hpbw, sll, peak_angle));
                notify(obj, 'ScanCompleted');
            end
        end

        function pauseScan(obj)
            if strcmpi(obj.AcquisitionMode,'Continuous') && obj.IsRunning
                obj.logStatus('Quét liên tục: dùng STOP để dừng motor.'); return;
            end
            if obj.IsRunning && ~obj.IsPaused
                obj.IsPaused = true;
                obj.setState('PAUSED');
                obj.logStatus('Scan paused.');
            end
        end

        function resumeScan(obj)
            if obj.IsRunning && obj.IsPaused
                obj.IsPaused = false;
                obj.setState('SCANNING');
                obj.logStatus('Scan resumed.');
            end
        end

        function abortScan(obj)
            if obj.IsRunning
                obj.CancelRequested = true;
                obj.IsPaused = false;
                obj.Positioner.requestAbort();
                obj.logStatus('Đang dừng quét sau bước hiện tại...');
            end
        end
    end

    methods (Static)
        function metadata = validateInstrumentProvenance(sweep,previous)
            metadata=previous;
            if ~isfield(sweep,'InstrumentMetadata'), return; end
            if ~isfield(sweep,'AcquisitionSource') || ~strcmp(sweep.AcquisitionSource,'FreshSingleSweep')
                error('MeasurementOrchestrator:StaleSweep','A scan requires a fresh completed sweep.');
            end
            current=sweep.InstrumentMetadata;
            if isempty(fieldnames(previous)), metadata=current; return; end
            before=previous; after=current;
            if isfield(before,'Timestamp'), before=rmfield(before,'Timestamp'); end
            if isfield(after,'Timestamp'), after=rmfield(after,'Timestamp'); end
            if ~isequal(before,after)
                error('MeasurementOrchestrator:InstrumentStateChanged', ...
                    'Instrument identity, correction or IF bandwidth changed; preserving committed points.');
            end
        end

        function angles = buildAngleVector(startDeg, stopDeg, stepDeg)
            % BUILDANGLEVECTOR Angle list for a scan. Decreasing pan angles are CW.
            stepDeg = abs(double(stepDeg));
            if isnan(startDeg) || isnan(stopDeg) || isnan(stepDeg) || stepDeg <= 0
                error('MeasurementOrchestrator:InvalidAngles', ...
                      'Start, Stop phải là số và Step phải > 0.');
            end
            if startDeg == stopDeg
                error('MeasurementOrchestrator:InvalidAngles', ...
                      'Start và Stop không được bằng nhau.');
            end
            if stopDeg > startDeg
                angles = startDeg:stepDeg:stopDeg;
            else
                angles = startDeg:-stepDeg:stopDeg;
            end
            % Make sure the final point lands exactly on Stop
            if abs(angles(end) - stopDeg) > 1e-9
                angles(end+1) = stopDeg;
            end
        end
    end

    methods (Access = private)
        function data = startScan3D(obj)
            if obj.IsRunning
                error('MeasurementOrchestrator:AlreadyRunning','A scan is already in progress.');
            end
            % Validate the entire plan BEFORE moving either motor.
            cfg = obj.Scan3DConfig;
            plan = ScanGeometry.buildPlan(cfg);
            mode=validatestring(obj.AcquisitionMode,{'Stepwise','Continuous'});
            continuous=strcmp(mode,'Continuous');
            if continuous && (~ismember(obj.VNA.Mode,{'ShockLine','Mock'}) || numel(plan.PanVector)<2)
                error('MeasurementOrchestrator:ContinuousMode','Continuous 3D requires ShockLine and distinct Pan endpoints.');
            end
            obj.CancelRequested = false; obj.IsPaused = false; obj.IsRunning = true;
            obj.TotalSteps = int32(numel(plan.PanMotorDeg)); obj.CurrentIndex=0; obj.Progress=0;
            cleanup = onCleanup(@() obj.resetRunning());
            obj.setState('INITIALIZING');
            try
            if ~obj.Positioner.IsConnected, obj.Positioner.connect(); end
            if obj.Positioner.TiltDisabled
                error('MeasurementOrchestrator:TiltDisabled','Enable verified Tilt feedback before a 3D scan.');
            end
            if ~obj.Positioner.IsHomed || obj.Positioner.ManualHomingActive
                error('MeasurementOrchestrator:ManualHomingRequired','Lock and ZERO both axes before scanning.');
            end
            if obj.Positioner.HoldingSupported && ~obj.Positioner.HoldingActive
                error('MeasurementOrchestrator:HoldLost','Holding torque is unavailable.');
            end
            if strcmpi(obj.Positioner.Mode,'Mock')
                obj.Positioner.setTravelLimits(cfg.TravelPanDeg,cfg.TravelTiltDeg);
            elseif ~obj.Positioner.FreeRotationSupported && (~obj.Positioner.TravelConfirmed || ...
                    ~isequal(cfg.TravelPanDeg,obj.Positioner.TravelPanDeg) || ...
                    ~isequal(cfg.TravelTiltDeg,obj.Positioner.TravelTiltDeg))
                error('MeasurementOrchestrator:TravelUnconfirmed','Confirm reachable travel for this mechanical ZERO before a 3D scan.');
            end
            obj.Positioner.validateTargets('AZ',plan.PanVector);
            obj.Positioner.validateTargets('EL',plan.TiltVector);
            if continuous && ~obj.Positioner.ContinuousPanSupported
                error('PositionerController:ContinuousUnsupported','Upload continuous-scan firmware before starting a continuous 3D scan.');
            end
            obj.readBothAxes();
            if obj.CancelRequested
                data=[]; obj.setState('ABORTED'); notify(obj,'ScanAborted'); return;
            end
            if ~isfinite(obj.CenterFreqHz) || ~isfinite(obj.SpanHz) || obj.SpanHz<=0 || ...
                    obj.CenterFreqHz-obj.SpanHz/2<=0 || obj.SweepPoints<2 || ...
                    ~isfinite(obj.SettleTimeSec) || obj.SettleTimeSec<0
                error('MeasurementOrchestrator:InvalidSweep','Use a positive frequency band, at least two VNA points and nonnegative settling.');
            end
            if ~obj.VNA.IsConnected, obj.VNA.connect(); end
            startHz = obj.CenterFreqHz-obj.SpanHz/2; stopHz = obj.CenterFreqHz+obj.SpanHz/2;
            obj.VNA.configureSweep(startHz,stopHz,obj.SweepPoints);
            catch ME
                if obj.CancelRequested
                    data=[]; obj.setState('ABORTED'); notify(obj,'ScanAborted'); return;
                end
                obj.setState('ERROR'); rethrow(ME);
            end
            if ~obj.awaitScan3D()
                data=[]; obj.setState('ABORTED'); notify(obj,'ScanAborted'); return;
            end
            n = numel(plan.PanMotorDeg); nf = double(obj.SweepPoints);
            s11 = complex(nan(n,nf)); s21 = s11;
            panMeasured = nan(1,n); tiltMeasured = panMeasured;
            panEncoder = panMeasured; tiltEncoder = panMeasured; elapsed = panMeasured;
            sweepStartPan=panMeasured; sweepEndPan=panMeasured;
            sweepStartSec=panMeasured; sweepEndSec=panMeasured;
            encoderStartMs=panMeasured; encoderEndMs=panMeasured;
            frequencies = linspace(startHz,stopHz,nf);
            committedInstrumentMetadata=struct();
            [~,centerIndex] = min(abs(frequencies-obj.CenterFreqHz));
            obj.TotalSteps = int32(n); obj.CurrentIndex = 0; obj.Progress = 0;
            obj.setState('SCANNING'); notify(obj,'ScanStarted');
            obj.logStatus(sprintf('3D scan: %d Tilt rows × %d Pan points; preserve mechanical ZERO.',numel(plan.TiltVector),numel(plan.PanVector)));
            done = 0; aborted = false; reason = ''; abortMessage = ''; scanClock = tic;
            sampled=false(1,n); completedContinuousRow=0; resolutionLimited=false;
            try
                previousRow = 0;
                for i = 1:n
                    if ~obj.awaitScan3D(), aborted = true; break; end
                    if continuous && plan.RowIndex(i)==completedContinuousRow, continue; end
                    atEndBefore=false;
                    if plan.RowIndex(i)~=previousRow
                        obj.logStatus(sprintf('Tilt row %d/%d: motor %.1f°, theta %.1f°.',plan.RowIndex(i),numel(plan.TiltVector),plan.TiltMotorDeg(i),plan.ThetaDeg(i)));
                        obj.Positioner.moveTo('EL',plan.TiltMotorDeg(i));
                        if ~obj.awaitScan3D(), aborted = true; break; end
                        obj.readBothAxes();
                        previousRow = plan.RowIndex(i);
                        if continuous
                            obj.Positioner.moveTo('AZ',plan.PanMotorDeg(i));
                        end
                    end
                    rowPoints=find(plan.RowIndex==plan.RowIndex(i));
                    if continuous && i~=rowPoints(1)
                        direction=sign(plan.PanMotorDeg(rowPoints(end))-plan.PanMotorDeg(rowPoints(1)));
                        pose=obj.Positioner.pollContinuousPan();
                        target=obj.continuousSampleTarget(pose.PanDeg,plan.PanMotorDeg(i), ...
                            plan.PanMotorDeg(rowPoints(1)),plan.PanMotorDeg(rowPoints(end)),cfg.PanStepDeg);
                        while direction*(pose.PanDeg-target)<0 && obj.Positioner.IsMoving
                            if ~obj.awaitScan3D(), break; end
                            pause(0.01); pose=obj.Positioner.pollContinuousPan();
                        end
                        atEndBefore=~obj.Positioner.IsMoving;
                    elseif ~continuous
                        obj.Positioner.moveTo('AZ',plan.PanMotorDeg(i));
                    end
                    if ~obj.awaitScan3D(), aborted = true; break; end
                    settling = tic;
                    while (~continuous || i==rowPoints(1)) && toc(settling)<obj.SettleTimeSec
                        if ~obj.awaitScan3D(), break; end
                        pause(min(0.05,max(0,obj.SettleTimeSec-toc(settling))));
                    end
                    if ~obj.awaitScan3D(), aborted = true; break; end
                    if continuous && i~=rowPoints(1)
                        before=obj.Positioner.pollContinuousPan();
                        panMeasured(i)=before.PanDeg; tiltMeasured(i)=before.TiltDeg;
                        panEncoder(i)=before.PanEncoderDeg; tiltEncoder(i)=before.TiltEncoderDeg;
                    else
                        [panMeasured(i),tiltMeasured(i),panEncoder(i),tiltEncoder(i)] = obj.readBothAxes();
                    end
                    sweepStartPan(i)=panMeasured(i); sweepStartSec(i)=toc(scanClock);
                    if strcmpi(obj.VNA.Mode,'Mock')
                        if continuous
                            obj.VNA.setMockOrientation(cfg.PanAtZeroDeg+cfg.PanSign*panMeasured(i), ...
                                cfg.TiltAtZeroDeg+cfg.TiltSign*tiltMeasured(i));
                        else
                            obj.VNA.setMockOrientation(plan.PhiDeg(i),plan.ThetaDeg(i));
                        end
                    end
                    if continuous && i~=rowPoints(1)
                        sweep=obj.VNA.acquireMovingSweep(@()obj.continuousPose(scanClock));
                    else
                        sweep=obj.VNA.acquireSingle();
                    end
                    sweepEndSec(i)=toc(scanClock); sweepEndPan(i)=sweepStartPan(i);
                    if continuous && i~=rowPoints(1) && ~obj.CancelRequested
                        before=sweep.MotionBefore; after=sweep.MotionAfter;
                        sweepStartPan(i)=before.PanDeg;
                        sweepEndPan(i)=after.PanDeg;
                        sweepStartSec(i)=before.ElapsedSec; sweepEndSec(i)=after.ElapsedSec;
                        encoderStartMs(i)=before.DeviceTimeMs; encoderEndMs(i)=after.DeviceTimeMs;
                        panMeasured(i)=(sweepStartPan(i)+sweepEndPan(i))/2;
                        panEncoder(i)=after.PanEncoderDeg;
                        spacing=abs(sweepEndPan(i)-sweepStartPan(i));
                        previous=find(sampled & plan.RowIndex==plan.RowIndex(i),1,'last');
                        if ~isempty(previous), spacing=max(spacing,abs(panMeasured(i)-panMeasured(previous))); end
                        resolutionLimited=obj.reportContinuousSpacing(resolutionLimited,spacing,cfg.PanStepDeg);
                        if i==rowPoints(end) || atEndBefore
                            obj.Positioner.endContinuousPan(false);
                            completedContinuousRow=plan.RowIndex(i);
                        end
                        [~,column]=min(abs(plan.PanVector-panMeasured(i)));
                        plan.ColumnIndex(i)=column; plan.PanMotorDeg(i)=plan.PanVector(column);
                    end
                    % STOP while acquiring may discard this uncommitted point.
                    if obj.CancelRequested, aborted = true; break; end
                    if numel(sweep.S11)~=nf || numel(sweep.S21)~=nf || ...
                            any(~isfinite(sweep.S11)) || any(~isfinite(sweep.S21)) || ...
                            numel(sweep.FrequencyHz)~=nf || any(~isfinite(sweep.FrequencyHz)) || any(diff(sweep.FrequencyHz)<=0)
                        error('MeasurementOrchestrator:InvalidSweep','VNA returned an incomplete or invalid sweep.');
                    end
                    if done>0 && ~isequal(reshape(sweep.FrequencyHz,1,[]),frequencies)
                        error('MeasurementOrchestrator:InvalidSweep','VNA frequency grid changed during the scan.');
                    end
                    nextMetadata=MeasurementOrchestrator.validateInstrumentProvenance(sweep,committedInstrumentMetadata);
                    committedInstrumentMetadata=nextMetadata;
                    frequencies = reshape(sweep.FrequencyHz,1,[]);
                    [~,centerIndex] = min(abs(frequencies-obj.CenterFreqHz));
                    s11(i,:) = sweep.S11; s21(i,:) = sweep.S21;
                    sampled(i)=true; done=done+1; elapsed(i) = toc(scanClock);
                    obj.CurrentIndex = int32(done); obj.Progress = i/n;
                    if continuous
                        extent=abs(cfg.PanStopDeg-cfg.PanStartDeg);
                        fraction=min(1,abs(panMeasured(i)-plan.PanMotorDeg(rowPoints(1)))/extent);
                        obj.Progress=(plan.RowIndex(i)-1+fraction)/numel(plan.TiltVector);
                    end
                    if ~isempty(obj.StepCallback)
                        callbackTheta=plan.ThetaDeg(i); callbackPhi=plan.PhiDeg(i);
                        if continuous
                            callbackTheta=cfg.TiltAtZeroDeg+cfg.TiltSign*tiltMeasured(i);
                            callbackPhi=cfg.PanAtZeroDeg+cfg.PanSign*panMeasured(i);
                        end
                        info = struct('Index',done,'Total',n,'CommandedAngle',plan.PanMotorDeg(i), ...
                            'MeasuredAngle',panMeasured(i),'EncoderAngle',panEncoder(i), ...
                            'PanAngle',plan.PanMotorDeg(i),'TiltAngle',plan.TiltMotorDeg(i), ...
                            'MeasuredPanAngle',panMeasured(i),'MeasuredTiltAngle',tiltMeasured(i), ...
                            'TiltEncoderAngle',tiltEncoder(i),'ThetaDeg',callbackTheta, ...
                            'PhiDeg',callbackPhi,'RowIndex',plan.RowIndex(i), ...
                            'ColumnIndex',plan.ColumnIndex(i),'TotalRows',numel(plan.TiltVector), ...
                            'S21_dB_Center',20*log10(max(abs(sweep.S21(centerIndex)),1e-12)), ...
                            'Progress',obj.Progress,'ElapsedSec',elapsed(i));
                        obj.StepCallback(info);
                    end
                    notify(obj,'StepProgress');
                    if continuous && i==rowPoints(1) && ~obj.CancelRequested
                        obj.Positioner.beginContinuousPan(plan.PanMotorDeg(rowPoints(end)));
                    end
                end
            catch ME
                aborted = true;
                abortMessage = ME.message;
                if contains(ME.identifier,'EncoderUnavailable')
                    reason = 'EncoderUnavailable';
                else
                    reason = ME.identifier;
                end
                obj.logStatus(sprintf('3D scan stopped: %s; preserving %d points.',ME.message,done));
            end
            if continuous
                try
                    obj.Positioner.endContinuousPan();
                catch ME
                    aborted=true; reason=ME.identifier; abortMessage=ME.message;
                    obj.logStatus(['Continuous motion cleanup: ' ME.message]);
                end
            end
            if obj.CancelRequested, aborted = true; if isempty(reason), reason = 'UserStop'; end; end
            if done==0
                data = []; obj.setState('ABORTED'); notify(obj,'ScanAborted'); return;
            end
            keep = find(sampled); s11 = s11(keep,:); s21 = s21(keep,:);
            rawDB = 20*log10(max(abs(s21(:,centerIndex)),1e-12)).';
            [peakDB,peakIndex] = max(rawDB);
            peakSample=keep(peakIndex);
            metadata = struct('SchemaVersion',2,'ScanAxis','3D','Scan3DConfig',cfg, ...
                'AcquisitionMode',mode,'MotionStopConfirmed',~obj.Positioner.IsMoving, ...
                'Device',obj.VNA.deviceName(),'VNAIdentity',obj.VNA.DeviceIdentity, ...
                'InstrumentMetadata',committedInstrumentMetadata,'VNAMode',obj.VNA.Mode,'VNAPort',obj.VNA.Port, ...
                'PositionerMode',obj.Positioner.Mode,'PositionerPort',obj.Positioner.Port, ...
                'AngleSource','Commanded positioner angles; encoder on motor shaft', ...
                'EncoderLocation','Motor shaft, modulo 360 deg; reduction 90/16', ...
                'CoordinateFrame','Declared theta/phi frame relative to manual ZERO', ...
                'TotalAngles',n,'CompletedPoints',done,'Aborted',aborted,'AbortReason',reason, ...
                'AbortMessage',abortMessage, ...
                'CenterFreqHz',obj.CenterFreqHz,'SpanHz',obj.SpanHz,'SweepPoints',nf, ...
                'SettleTimeSec',obj.SettleTimeSec,'TotalTimeSec',toc(scanClock), ...
                'AngleStepDeg',cfg.PanStepDeg,'Firmware','Positioner capability reported over POS', ...
                'Timestamp',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
            analysis = struct('PeakVal_dB',peakDB,'PeakPan_deg',plan.PanMotorDeg(peakSample), ...
                'PeakTilt_deg',plan.TiltMotorDeg(peakSample),'PeakTheta_deg',plan.ThetaDeg(peakSample), ...
                'PeakPhi_deg',mod(plan.PhiDeg(peakSample),360));
            data = struct('Metadata',metadata,'Analysis',analysis,'Angles',plan.PanMotorDeg(keep), ...
                'PanAngles',plan.PanMotorDeg(keep),'TiltAngles',plan.TiltMotorDeg(keep), ...
                'ThetaDeg',plan.ThetaDeg(keep),'PhiDeg',plan.PhiDeg(keep), ...
                'PhiWrappedDeg',mod(plan.PhiDeg(keep),360), ...
                'MeasuredAngles',panMeasured(keep),'MeasuredPanAngles',panMeasured(keep), ...
                'MeasuredTiltAngles',tiltMeasured(keep),'EncoderAngles',panEncoder(keep), ...
                'PanEncoderAngles',panEncoder(keep),'TiltEncoderAngles',tiltEncoder(keep), ...
                'EncoderValid',isfinite(panEncoder(keep)) & isfinite(tiltEncoder(keep)), ...
                'RowIndex',plan.RowIndex(keep),'ColumnIndex',plan.ColumnIndex(keep), ...
                'ElapsedSec',elapsed(keep),'FrequenciesHz',frequencies,'SelectedFreqHz',obj.CenterFreqHz, ...
                'S11',s11,'S21',s21,'SelectedS21_dB',rawDB, ...
                'SelectedS21_PhaseDeg',rad2deg(angle(s21(:,centerIndex))).', ...
                'NormalizedS21_dB',PatternAnalyzer.normalize(rawDB));
            if continuous
                metadata.AngleSource='Pan motor-shaft encoder unwrapped relative to row start; sweep midpoint';
                metadata.EncoderPolarity='Inferred from commanded direction and initial encoder displacement';
                metadata.ResolutionLimited=resolutionLimited;
                metadata.RequestedTotalAngles=n;
                gaps=abs(diff(panMeasured(keep)));
                sameRow=diff(plan.RowIndex(keep))==0;
                metadata.MaxMeasuredGapDeg=max([0 gaps(sameRow)]);
                metadata.MaxSweepAngularSpanDeg=max(abs(sweepEndPan(keep)-sweepStartPan(keep)));
                metadata.AngleTiming='Sampled brackets around trigger/completion acknowledgement; approximately 100 ms telemetry plus TCP latency';
                data.Metadata=metadata;
                data.SweepStartPanDeg=sweepStartPan(keep); data.SweepEndPanDeg=sweepEndPan(keep);
                data.SweepStartSec=sweepStartSec(keep); data.SweepEndSec=sweepEndSec(keep);
                data.EncoderStartTimeMs=encoderStartMs(keep); data.EncoderEndTimeMs=encoderEndMs(keep);
                data.PhiDeg=cfg.PanAtZeroDeg+cfg.PanSign*data.MeasuredPanAngles;
                data.ThetaDeg=cfg.TiltAtZeroDeg+cfg.TiltSign*data.MeasuredTiltAngles;
                data.PhiWrappedDeg=mod(data.PhiDeg,360);
                data.Analysis.PeakPan_deg=data.MeasuredPanAngles(peakIndex);
                data.Analysis.PeakPhi_deg=data.PhiWrappedDeg(peakIndex);
            end
            obj.LastScanData = data;
            if aborted
                obj.setState('ABORTED'); notify(obj,'ScanAborted');
            else
                obj.Progress=1;
                obj.setState('COMPLETED'); notify(obj,'ScanCompleted');
            end
            obj.logStatus(sprintf('3D %s: %d/%d points retained.',obj.State,done,n));
        end

        function ready = awaitScan3D(obj)
            drawnow limitrate;
            while obj.IsPaused && ~obj.CancelRequested, pause(0.05); end
            ready = ~obj.CancelRequested;
        end

        function pose=continuousPose(obj,scanClock)
            if obj.CancelRequested
                error('PositionerController:Aborted','Continuous scan was stopped.');
            end
            pose=obj.Positioner.pollContinuousPan();
            pose.ElapsedSec=toc(scanClock);
        end

        function angle=axisPoseAngle(obj,pose)
            angle=pose.PanDeg;
            if strcmpi(obj.Axis,'EL'), angle=pose.TiltDeg; end
        end

        function target=continuousSampleTarget(~,actual,nominal,first,last,step)
            direction=sign(last-first); step=abs(step);
            target=nominal;
            if direction*(actual-nominal)>0
                distance=ceil(max(0,direction*(actual-first))/step)*step;
                target=first+direction*min(abs(last-first),distance);
            end
        end

        function limited=reportContinuousSpacing(obj,limited,spacing,step)
            if spacing>abs(step)*1.1
                if ~limited
                    obj.logStatus(sprintf('Quét liên tục: VNA chậm hơn lưới %.2f°; lưu góc encoder thực. Mẫu sẽ thưa hơn bước đã chọn.',abs(step)));
                end
                limited=true;
            end
        end

        function [pan,tilt,panEncoder,tiltEncoder] = readBothAxes(obj)
            [pan,panEncoder] = obj.Positioner.getPositionSnapshot('AZ',true);
            [tilt,tiltEncoder] = obj.Positioner.getPositionSnapshot('EL',false);
            if ~obj.Positioner.IsHomed || obj.Positioner.ManualHomingActive
                error('MeasurementOrchestrator:ManualHomingRequired','Mechanical ZERO was lost; recalibrate both axes.');
            end
            if obj.Positioner.HoldingSupported && ~obj.Positioner.HoldingActive
                error('MeasurementOrchestrator:HoldLost','Holding torque was lost during the scan.');
            end
            if ~isfinite(panEncoder) || ~isfinite(tiltEncoder) || panEncoder<0 || tiltEncoder<0
                error('PositionerController:EncoderUnavailable','Both AS5600 encoders must be valid for 3D acquisition.');
            end
        end

        function resetRunning(obj)
            if isvalid(obj)
                obj.IsRunning = false;
                obj.IsPaused = false;
            end
        end

        function setState(obj, newState)
            obj.State = newState;
        end

        function logStatus(obj, msg)
            if ~isempty(obj.StatusCallback)
                obj.StatusCallback(msg);
            else
                fprintf('[ORCHESTRATOR] %s\n', msg);
            end
        end
    end
end
