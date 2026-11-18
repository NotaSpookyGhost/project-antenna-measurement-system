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

        function [sll_db, sll_angle_deg] = calculateSLL(angles_deg, s21_rel_db, hpbw_deg)
            % CALCULATESLL Calculate Side-Lobe Level (relative to main lobe peak = 0 dB).
            %
            % Identifies local maxima outside the main lobe beamwidth.
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

            if max(s21_rel_db) > 0.05 || max(s21_rel_db) < -0.05
                s21_rel_db = PatternAnalyzer.normalize(s21_rel_db);
            end

            [peak_val, peak_idx] = max(s21_rel_db);
            peak_angle = angles_deg(peak_idx);

            if nargin < 3 || isnan(hpbw_deg)
                [hpbw_deg, ~, ~] = PatternAnalyzer.calculateHPBW(angles_deg, s21_rel_db);
                if isnan(hpbw_deg)
                    hpbw_deg = 30.0; % Default reasonable assumption if beamwidth cannot be resolved
                end
            end

            % Define exclusion zone for main lobe: at least 0.75 * HPBW away from peak
            exclusion_half = max(hpbw_deg * 0.75, 5.0);

            N = length(angles_deg);
            sidelobe_peaks = [];
            sidelobe_angles = [];

            for i = 1:N
                prev_i = mod(i-2, N) + 1;
                next_i = mod(i, N) + 1;

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

        function limits = measuredDBLimits(s21_db, minimum_span_db)
            % Include every measured level; never subtract the measured peak.
            if nargin < 2, minimum_span_db = 40; end
            values = s21_db(isfinite(s21_db));
            if isempty(values), limits = [-minimum_span_db 0]; return; end
            upper = 5 * ceil((max(values) + 1) / 5);
            lower = min(5 * floor((min(values) - 1) / 5), upper - minimum_span_db);
            limits = [lower upper];
        end

        function h_lines = plotPolar(ax, angles_deg, s21_db, title_str, dynamic_range_db, parameter)
            if nargin<6, parameter='S21'; end
            % Plot measured S21 at its original angles and dB levels.
            if isempty(angles_deg) || isempty(s21_db), h_lines = []; return; end
            if nargin < 4 || isempty(title_str), title_str = ['Measured ' parameter ' (2D Polar, dB)']; end
            if nargin < 5 || isempty(dynamic_range_db), dynamic_range_db = 40; end
            if isempty(ax)
                figure('Name', title_str, 'Color', 'w'); ax = polaraxes();
            end
            cla(ax);
            h_lines = polarplot(ax, deg2rad(angles_deg), s21_db, 'b.-', 'LineWidth', 1.8);
            ax.RLim = PatternAnalyzer.measuredDBLimits(s21_db, dynamic_range_db);
            ax.ThetaZeroLocation = 'top'; ax.ThetaDir = 'clockwise';
            title(ax, title_str, 'FontWeight', 'bold');
        end

        function h_plot = plotCartesian(ax, angles_deg, s21_db, title_str, dynamic_range_db, parameter)
            if nargin<6, parameter='S21'; end
            % Plot measured S21 without peak normalization or gain conversion.
            if isempty(angles_deg) || isempty(s21_db), h_plot = []; return; end
            if nargin < 4 || isempty(title_str), title_str = ['Measured ' parameter ' vs Angle']; end
            if nargin < 5 || isempty(dynamic_range_db), dynamic_range_db = 40; end
            if isempty(ax)
                figure('Name', title_str, 'Color', 'w'); ax = gca();
            end
            cla(ax);
            h_plot = plot(ax, angles_deg, s21_db, 'b.-', 'LineWidth', 1.8);
            grid(ax, 'on'); xlabel(ax, 'Angle (deg)'); ylabel(ax, [parameter ' (dB)']);
            ylim(ax, PatternAnalyzer.measuredDBLimits(s21_db, dynamic_range_db));
            angleLimits = [min(angles_deg), max(angles_deg)];
            if angleLimits(1) == angleLimits(2), angleLimits = angleLimits + [-1 1]; end
            xlim(ax, angleLimits); title(ax, title_str, 'FontWeight', 'bold');
        end
    end
end
