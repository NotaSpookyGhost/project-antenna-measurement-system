function view_scan_dataset(scan_file_or_dir)
    % VIEW_SCAN_DATASET Standalone Post-Processor and Visualizer for Antenna Scans.
    %
    % Loads any previously acquired scan dataset (.mat or directory) and generates:
    %   1. 2D Polar Radiation Pattern with HPBW and SLL markers
    %   2. 2D Cartesian Pattern (Angle vs Relative Transmission in dB)
    %   3. RF Frequency Domain Trace (|S21| & |S11| at peak angle)
    %   4. 3D Radiation Pattern Surface Model
    %
    % Usage:
    %   view_scan_dataset()               % Opens file selection dialog
    %   view_scan_dataset('data/scans/sim_azimuth_20260930_142316')
    %   view_scan_dataset('data/scans/sim_azimuth_20260930_142316/scan_data.mat')

    matlab_dir = fileparts(mfilename('fullpath')); % projects/matlab
    addpath(fullfile(matlab_dir, 'classes'));

    if nargin < 1 || isempty(scan_file_or_dir)
        [file, path] = uigetfile('*.mat', 'Select scan_data.mat file');
        if isequal(file, 0), return; end
        scan_file_or_dir = fullfile(path, file);
    end

    fprintf('============================================================\n');
    fprintf('  Antenna Scan Dataset Post-Processor & Visualizer\n');
    fprintf('============================================================\n');
    fprintf('Loading: %s\n\n', scan_file_or_dir);

    % Load via DataManager
    scanData = DataManager.loadScanDataset(scan_file_or_dir);
    meta = scanData.Metadata;
    an = scanData.Analysis;

    % Print Summary
    fprintf('--- METADATA -----------------------------------------------\n');
    fprintf('Device:            %s (Port: %s, Mode: %s)\n', meta.Device, meta.VNAPort, meta.VNAMode);
    fprintf('Positioner:        %s (%s)\n', meta.PositionerMode, meta.ScanAxis);
    fprintf('Timestamp:         %s\n', meta.Timestamp);
    fprintf('Center Frequency:  %.3f MHz\n', scanData.SelectedFreqHz / 1e6);
    fprintf('Angle Range:       %.1f° to %.1f° (Step: %.2f°, %d points)\n', ...
            min(scanData.Angles), max(scanData.Angles), meta.AngleStepDeg, length(scanData.Angles));
    fprintf('Total Scan Time:   %.2f s (%.3f s/point)\n', meta.TotalTimeSec, meta.TotalTimeSec / length(scanData.Angles));
    fprintf('------------------------------------------------------------\n');
    fprintf('--- COMPUTED METRICS ---------------------------------------\n');
    fprintf('Main Lobe Peak:    %.2f dB at %.2f°\n', an.PeakVal_dB, an.PeakAngle_deg);
    fprintf('HPBW (-3 dB):      %.2f° (Left: %.2f°, Right: %.2f°)\n', ...
            an.HPBW_deg, an.ThetaLeft_deg, an.ThetaRight_deg);
    fprintf('Side-Lobe Level:   %.2f dB at %.2f°\n', an.SLL_dB, an.SLLAngle_deg);
    fprintf('Front-to-Back:     %.2f dB\n', an.FBR_dB);
    fprintf('============================================================\n\n');

    % Create 4-Subplot Comprehensive Figure
    fig = figure('Name', sprintf('Scan Analysis — %s (%.1f MHz)', meta.Device, scanData.SelectedFreqHz/1e6), ...
                 'Position', [80, 80, 1150, 700], 'Color', 'w');

    % 1. 2D Polar
    ax1 = subplot(2, 2, 1, polaraxes);
    PatternAnalyzer.plotPolar(ax1, scanData.Angles, scanData.NormalizedS21_dB, ...
        sprintf('2D Polar Pattern — %.3f MHz', scanData.SelectedFreqHz/1e6));

    % 2. 2D Cartesian
    ax2 = subplot(2, 2, 2);
    PatternAnalyzer.plotCartesian(ax2, scanData.Angles, scanData.NormalizedS21_dB, ...
        sprintf('2D Cartesian Pattern (HPBW: %.1f°, SLL: %.1f dB)', an.HPBW_deg, an.SLL_dB),[],an);

    % 3. RF Sweep Monitor at Peak
    ax3 = subplot(2, 2, 3);
    [~, peak_i] = max(scanData.SelectedS21_dB);
    freq_mhz = scanData.FrequenciesHz / 1e6;
    plot(ax3, freq_mhz, 20*log10(abs(scanData.S21(peak_i, :))), 'b-o', 'LineWidth', 1.5, 'MarkerSize', 4);
    hold(ax3, 'on');
    plot(ax3, freq_mhz, 20*log10(abs(scanData.S11(peak_i, :))), 'r-s', 'LineWidth', 1.5, 'MarkerSize', 4);
    grid(ax3, 'on');
    legend(ax3, '|S21| Forward Transmission', '|S11| Return Loss', 'Location', 'best');
    title(ax3, sprintf('RF Traces at Peak Angle (%.1f°)', scanData.Angles(peak_i)), 'FontWeight', 'bold');
    xlabel(ax3, 'Frequency (MHz)'); ylabel(ax3, 'Magnitude (dB)');

    % 4. 3D Surface Model
    ax4 = subplot(2, 2, 4);
    phi = deg2rad(scanData.Angles);
    theta = deg2rad(linspace(-90, 90, 30));
    [THETA, PHI] = meshgrid(theta, phi);
    r_db = repmat(scanData.NormalizedS21_dB(:), 1, length(theta)) + 20*log10(max(cos(THETA), 0.05));
    r_db = max(r_db, -35.0);
    R = r_db - min(r_db(:)) + 5.0;
    [X, Y, Z] = sph2cart(PHI, THETA, R);
    surf(ax4, X, Y, Z, r_db, 'EdgeColor', 'none');
    axis(ax4, 'equal'); grid(ax4, 'on');
    view(ax4, 45, 30);
    colormap(ax4, 'jet');
    cb = colorbar(ax4);
    cb.Label.String = 'Relative S21 (dB)';
    title(ax4, '3D Radiation Pattern Model', 'FontWeight', 'bold');

    sgtitle(sprintf('Antenna Measurement Analysis — Peak: %.1f° | HPBW: %.1f° | SLL: %.1f dB | FBR: %.1f dB', ...
            an.PeakAngle_deg, an.HPBW_deg, an.SLL_dB, an.FBR_dB), 'FontWeight', 'bold');

    fprintf('Visualization figure generated.\n');
end
