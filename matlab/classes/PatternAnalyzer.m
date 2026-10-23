classdef PatternAnalyzer
    % PATTERNANALYZER Antenna radiation pattern numerical analysis and visualization.
    %
    % Implements core antenna characterization metrics per master document §14:
    %   - Normalization (Peak = 0 dB)
    %   - Half-Power Beamwidth (HPBW / 3-dB beamwidth) with sub-degree interpolation
    %   - Side-Lobe Level (SLL) detection and identification
    %   - Front-to-Back Ratio (FBR)
    %   - Gain estimation framework (Substitution method)
    %   - Synthetic antenna pattern generation for simulation and unit testing
    %   - 2D Polar, 2D Cartesian, and 3D spherical visualization
    %
    % Author: Antenna Measurement Automation Team
    % Version: 1.0 (MATLAB R2025b compatible)

    methods (Static)

        function s21_rel_db = normalize(s21_db)
            % NORMALIZE Normalize S21 curve to peak = 0 dB.
            %   s21_rel_db = normalize(s21_db)
            if isempty(s21_db)
                s21_rel_db = [];
                return;
            end
            max_val = max(s21_db(:));
            s21_rel_db = s21_db - max_val;
        end

        function [peak_angle, peak_val] = findMainLobe(angles_deg, s21_db)
            % FINDMAINLOBE Find main beam peak angle and magnitude.
            %   [peak_angle, peak_val] = findMainLobe(angles_deg, s21_db)
            if isempty(angles_deg) || isempty(s21_db)
                peak_angle = NaN;
                peak_val = NaN;
                return;
            end
            [peak_val, idx] = max(s21_db);
            peak_angle = angles_deg(idx);
        end

        function [hpbw_deg, theta_left, theta_right] = calculateHPBW(angles_deg, s21_rel_db)
            % CALCULATEHPBW Calculate Half-Power Beamwidth (-3 dB beamwidth).
            % Uses interpolation around the -3 dB crossing points for sub-degree accuracy.
            %
            % Inputs:
            %   angles_deg: 1D array of scan angles (e.g. 0:1:359 or -180:1:180)
            %   s21_rel_db: 1D array of normalized S21 in dB (peak should be 0 dB)
            %
            % Outputs:
            %   hpbw_deg: 3-dB beamwidth in degrees
            %   theta_left: Angle of left -3 dB crossing
            %   theta_right: Angle of right -3 dB crossing

            angles_deg = angles_deg(:)';
            s21_rel_db = s21_rel_db(:)';

            if length(angles_deg) < 3 || isempty(s21_rel_db)
                hpbw_deg = NaN;
                theta_left = NaN;
                theta_right = NaN;
                return;
            end

            % Ensure normalized (peak = 0 dB)
            if max(s21_rel_db) > 0.05 || max(s21_rel_db) < -0.05
                s21_rel_db = PatternAnalyzer.normalize(s21_rel_db);
            end

            [~, max_idx] = max(s21_rel_db);
            N = length(angles_deg);

            % Shift coordinate so peak is at center to simplify circular boundary handling
            shift_offset = max_idx - round(N/2);
            shifted_angles = circshift(angles_deg, -shift_offset);
            shifted_s21 = circshift(s21_rel_db, -shift_offset);

            % Unwrap angles around peak to be monotonic
            peak_angle = shifted_angles(round(N/2));
            unwrapped_angles = shifted_angles;
            for i = 1:N
                diff = unwrapped_angles(i) - peak_angle;
                while diff > 180, diff = diff - 360; end
                while diff < -180, diff = diff + 360; end
                unwrapped_angles(i) = peak_angle + diff;
            end
            [unwrapped_angles, sort_idx] = sort(unwrapped_angles);
            shifted_s21 = shifted_s21(sort_idx);

            % Find center index in sorted array
            [~, center_idx] = max(shifted_s21);

            % Search Left of peak for -3 dB crossing
            theta_left = NaN;
            for i = center_idx:-1:2
                if shifted_s21(i) >= -3.0 && shifted_s21(i-1) < -3.0
                    % Linear interpolation between i and i-1
                    x1 = unwrapped_angles(i); y1 = shifted_s21(i);
                    x0 = unwrapped_angles(i-1); y0 = shifted_s21(i-1);
                    if y1 ~= y0
                        theta_left = x0 + (-3.0 - y0) * (x1 - x0) / (y1 - y0);
                    else
                        theta_left = x1;
                    end
                    break;
                end
            end

            % Search Right of peak for -3 dB crossing
            theta_right = NaN;
            for i = center_idx:1:(N-1)
                if shifted_s21(i) >= -3.0 && shifted_s21(i+1) < -3.0
                    % Linear interpolation between i and i+1
                    x0 = unwrapped_angles(i); y0 = shifted_s21(i);
                    x1 = unwrapped_angles(i+1); y1 = shifted_s21(i+1);
                    if y1 ~= y0
                        theta_right = x0 + (-3.0 - y0) * (x1 - x0) / (y1 - y0);
                    else
                        theta_right = x0;
                    end
                    break;
                end
            end

            if isnan(theta_left) || isnan(theta_right)
                hpbw_deg = NaN;
            else
                hpbw_deg = abs(theta_right - theta_left);
            end
        end

        function [sll_db, sll_angle_deg] = calculateSLL(angles_deg, s21_rel_db, hpbw_deg, fullCircle)
            % CALCULATESLL Calculate Side-Lobe Level (relative to main lobe peak = 0 dB).
            %
            % Identifies local maxima outside the main lobe beamwidth.
            % Optional fullCircle declares scan topology when known. Otherwise,
            % infer a repeated endpoint or a uniform grid spanning 360-step.
            % Pass false for sectors, including an ambiguous 0:359 sector.
            % Returns:
            %   sll_db: Highest sidelobe peak in dB (typically negative, e.g. -13.5 dB)
            %   sll_angle_deg: Angle at which the highest sidelobe occurs

            angles_deg = angles_deg(:)';
            s21_rel_db = s21_rel_db(:)';

            if length(angles_deg) < 3 || isempty(s21_rel_db)
                sll_db = NaN;
                sll_angle_deg = NaN;
                return;
            end

            [angles_deg,order]=sort(angles_deg);
            s21_rel_db=s21_rel_db(order);
            span=angles_deg(end)-angles_deg(1);
            duplicateEndpoint=abs(span-360)<=1e-8;
            if nargin<4 || isempty(fullCircle)
                steps=diff(angles_deg);
                step=steps(1);
                fullCircle=duplicateEndpoint || (step>0 && ...
                    all(abs(steps-step)<=1e-8) && abs(span+step-360)<=1e-8);
            end

            if max(s21_rel_db) > 0.05 || max(s21_rel_db) < -0.05
                s21_rel_db = PatternAnalyzer.normalize(s21_rel_db);
            end

            [~, peak_idx] = max(s21_rel_db);
            peak_angle = angles_deg(peak_idx);

            if nargin < 3 || isnan(hpbw_deg)
                [hpbw_deg, ~, ~] = PatternAnalyzer.calculateHPBW(angles_deg, s21_rel_db);
                if isnan(hpbw_deg)
                    sll_db = NaN;
                    sll_angle_deg = NaN;
                    return;
                end
            end

            % Define exclusion zone for main lobe: at least 0.75 * HPBW away from peak
            exclusion_half = max(hpbw_deg * 0.75, 5.0);

            N = length(angles_deg);
            sidelobe_peaks = [];
            sidelobe_angles = [];

            if fullCircle
                candidates=1:N;
            else
                candidates=2:(N-1);
            end
            for i = candidates
                if fullCircle
                    prev_i = mod(i-2, N) + 1;
                    next_i = mod(i, N) + 1;
                    % Closure repeats the same direction, not a neighbor.
                    if duplicateEndpoint
                        if i==1, prev_i=N-1; end
                        if i==N, next_i=2; end
                    end
                else
                    prev_i=i-1;
                    next_i=i+1;
                end

                % Check if local peak
                if s21_rel_db(i) > s21_rel_db(prev_i) && s21_rel_db(i) >= s21_rel_db(next_i)
                    % Angular distance to main peak
                    dist = abs(angles_deg(i) - peak_angle);
                    while dist > 180, dist = abs(dist - 360); end

                    if dist > exclusion_half
                        sidelobe_peaks(end+1) = s21_rel_db(i); %#ok<AGROW>
                        sidelobe_angles(end+1) = angles_deg(i); %#ok<AGROW>
                    end
                end
            end

            if isempty(sidelobe_peaks)
                sll_db = NaN;
                sll_angle_deg = NaN;
            else
                [sll_db, max_sll_idx] = max(sidelobe_peaks);
                sll_angle_deg = sidelobe_angles(max_sll_idx);
            end
        end

        function fbr_db = calculateFBR(angles_deg, s21_rel_db)
            % CALCULATEFBR Front-to-Back Ratio in dB.
            % Compares peak main beam to the maximum level in the back-lobe sector
            % (peak_angle +/- 180 deg +/- 30 deg).

            angles_deg = angles_deg(:)';
            s21_rel_db = s21_rel_db(:)';

            if length(angles_deg) < 3 || isempty(s21_rel_db)
                fbr_db = NaN;
                return;
            end

            if max(s21_rel_db) > 0.05 || max(s21_rel_db) < -0.05
                s21_rel_db = PatternAnalyzer.normalize(s21_rel_db);
            end

            [peak_val, peak_idx] = max(s21_rel_db);
            peak_angle = angles_deg(peak_idx);
            back_angle = peak_angle + 180;

            back_sector_vals = [];
            for i = 1:length(angles_deg)
                dist = abs(angles_deg(i) - back_angle);
                while dist > 180, dist = abs(dist - 360); end
                if dist <= 30.0
                    back_sector_vals(end+1) = s21_rel_db(i); %#ok<AGROW>
                end
            end

            if isempty(back_sector_vals)
                fbr_db = NaN;
            else
                max_back = max(back_sector_vals);
                fbr_db = peak_val - max_back; % In dB relative
            end
        end

        function gain_dut_dbi = estimateGain(s21_dut_peak_db, ref_gain_dbi, s21_ref_peak_db)
            % ESTIMATEGAIN Gain transfer substitution formula.
            %   Gain_DUT = Gain_REF + (S21_DUT - S21_REF)
            %
            % Inputs:
            %   s21_dut_peak_db: Measured S21 peak of Device Under Test
            %   ref_gain_dbi: Calibrated known gain of Reference Antenna in dBi
            %   s21_ref_peak_db: Measured S21 peak with Reference Antenna in place
            gain_dut_dbi = ref_gain_dbi + (s21_dut_peak_db - s21_ref_peak_db);
        end

        function s21_rel_db = generateSyntheticPattern(angles_deg, hpbw_target_deg, sll_target_db, peak_angle_deg, noise_floor_db)
            % GENERATESYNTHETICPATTERN Generate realistic microstrip patch array beam pattern.
            %
            % Useful for simulation, Mock VNA, and automated unit testing.
            % Model combines cosine/sinc patch array factor with side-lobes and noise floor.

            if nargin < 2 || isempty(hpbw_target_deg), hpbw_target_deg = 35.0; end
            if nargin < 3 || isempty(sll_target_db), sll_target_db = -13.5; end
            if nargin < 4 || isempty(peak_angle_deg), peak_angle_deg = 0.0; end
            if nargin < 5 || isempty(noise_floor_db), noise_floor_db = -45.0; end

            angles_deg = angles_deg(:)';
            % Wrap angle difference into [-180, 180] for proper circular symmetry
            theta_diff = mod(angles_deg - peak_angle_deg + 180, 360) - 180;
            theta_rad = deg2rad(theta_diff);

            % Linear array factor parameter k_u chosen to match hpbw_target_deg
            % For sinc(pi*u) = sin(pi*u)/(pi*u), -3 dB point is at u = 0.442946
            u = 0.442946 * sin(theta_rad) / sin(deg2rad(hpbw_target_deg / 2));
            u(abs(u) < 1e-9) = 1e-9;

            % Main array factor
            af = sin(pi * u) ./ (pi * u);
            af_mag = abs(af);

            % Element factor (Patch element cos(theta), front half-plane)
            ef = max(cos(theta_rad), 0.05);

            % Combined voltage pattern
            total_v = af_mag .* ef;

            % Convert to dB
            total_v(total_v < 1e-6) = 1e-6;
            pattern_db = 20 * log10(total_v);

            % Sidelobes shaping if needed
            sidelobe_mask = abs(theta_diff) > (hpbw_target_deg * 0.7);
            pattern_db(sidelobe_mask) = pattern_db(sidelobe_mask) + (sll_target_db - (-13.26));

            % Add noise floor
            pattern_db = max(pattern_db, noise_floor_db + 1.0 * (rand(size(pattern_db)) - 0.5));

            % Theoretical peak at theta_diff = 0 is exactly 0.0 dB
            s21_rel_db = min(pattern_db, 0.0);
        end

        function h_lines = plotPolar(ax, angles_deg, s21_rel_db, title_str, dynamic_range_db)
            % PLOTPOLAR Plot 2D polar radiation pattern with standard antenna conventions.
            %
            % Dynamic range defaults to 40 dB (inner = -40 dB, outer rim = 0 dB).

            if isempty(angles_deg) || isempty(s21_rel_db)
                h_lines = [];
                return;
            end

            if nargin < 4 || isempty(title_str), title_str = 'Radiation Pattern (2D Polar)'; end
            if nargin < 5 || isempty(dynamic_range_db), dynamic_range_db = 40.0; end

            s21_rel_db = PatternAnalyzer.normalize(s21_rel_db);
            r = max(s21_rel_db, -dynamic_range_db);

            theta_rad = deg2rad(angles_deg);

            % Use polaraxes if available
            if isempty(ax)
                figure('Name', title_str, 'Color', 'w');
                ax = polaraxes();
            end

            cla(ax);
            hold(ax, 'on');

            % Plot pattern
            h_main = polarplot(ax, theta_rad, r, 'b-', 'LineWidth', 2.0);

            % Annotate HPBW and peak
            [peak_angle, ~] = PatternAnalyzer.findMainLobe(angles_deg, s21_rel_db);
            [hpbw, th_left, th_right] = PatternAnalyzer.calculateHPBW(angles_deg, s21_rel_db);

            polarplot(ax, deg2rad(peak_angle), 0, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);

            if ~isnan(hpbw) && ~isnan(th_left) && ~isnan(th_right)
                polarplot(ax, [deg2rad(th_left), deg2rad(th_left)], [-dynamic_range_db, -3], 'r--', 'LineWidth', 1.2);
                polarplot(ax, [deg2rad(th_right), deg2rad(th_right)], [-dynamic_range_db, -3], 'r--', 'LineWidth', 1.2);
            end

            ax.RLim = [-dynamic_range_db, 0];
            ax.ThetaZeroLocation = 'top';
            ax.ThetaDir = 'clockwise';
            title(ax, title_str, 'FontWeight', 'bold');

            h_lines = h_main;
        end

        function h_plot = plotCartesian(ax, angles_deg, s21_rel_db, title_str, dynamic_range_db, analysis)
            % PLOTCARTESIAN Plot 2D Cartesian pattern (Angle vs Relative dB).
            % Optional scan analysis preserves the declared topology in annotations.

            if isempty(angles_deg) || isempty(s21_rel_db)
                h_plot = [];
                return;
            end

            if nargin < 4 || isempty(title_str), title_str = 'Radiation Pattern (Cartesian)'; end
            if nargin < 5 || isempty(dynamic_range_db), dynamic_range_db = 40.0; end

            s21_rel_db = PatternAnalyzer.normalize(s21_rel_db);

            if isempty(ax)
                figure('Name', title_str, 'Color', 'w');
                ax = gca();
            end

            cla(ax);
            hold(ax, 'on');

            % -3 dB reference line
            yline(ax, -3.0, 'r--', 'LineWidth', 1.2, 'Label', '-3 dB (HPBW threshold)');

            % Pattern curve
            h_plot = plot(ax, angles_deg, s21_rel_db, 'b-', 'LineWidth', 1.8);

            % Annotations
            if nargin<6 || isempty(analysis)
                [hpbw, th_l, th_r] = PatternAnalyzer.calculateHPBW(angles_deg, s21_rel_db);
                [sll, sll_th] = PatternAnalyzer.calculateSLL(angles_deg, s21_rel_db, hpbw);
            else
                th_l=analysis.ThetaLeft_deg; th_r=analysis.ThetaRight_deg;
                sll=analysis.SLL_dB; sll_th=analysis.SLLAngle_deg;
            end

            if ~isnan(th_l) && ~isnan(th_r)
                plot(ax, [th_l, th_r], [-3, -3], 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
            end
            if ~isnan(sll) && ~isnan(sll_th)
                plot(ax, sll_th, sll, 'ms', 'MarkerFaceColor', 'm', 'MarkerSize', 6);
                text(ax, sll_th, sll + 1.5, sprintf('SLL: %.1f dB', sll), 'Color', 'm', 'FontWeight', 'bold');
            end

            grid(ax, 'on');
            xlabel(ax, 'Angle (deg)');
            ylabel(ax, 'Relative Transmission (dB)');
            ylim(ax, [-dynamic_range_db, 2]);
            angleLimits = [min(angles_deg), max(angles_deg)];
            if angleLimits(1) == angleLimits(2)
                % A stopped scan or a one-point Pan slice still has valid data.
                angleLimits = angleLimits + [-1, 1];
                h_plot.Marker = 'o';
            end
            xlim(ax, angleLimits);
            title(ax, title_str, 'FontWeight', 'bold');
        end

    end
end
