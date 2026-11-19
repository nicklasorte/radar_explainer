function results = radar_explainer_rev1(opts)
%RADAR_EXPLAINER_REV1 Walk through a digital pulse-Doppler radar on one simulated scene.
%
%   results = radar_explainer_rev1() simulates two moving targets inside a
%   stationary clutter patch, runs the echoes through the digital blocks of a
%   pulse-Doppler radar, and saves one figure per stage in the "figures" folder.
%
%   The block numbers in this file match the block diagram (figure 0):
%
%     1  Waveform generator   Figure 1   Make the linear FM (LFM) chirp.
%     2-6 Analog RF chain      ideal      Not simulated. The code works at complex baseband.
%     7  ADC                  Figure 2   Quantize the I/Q samples.
%     8  Digital I/Q          ideal      The samples are already complex baseband.
%     9  Matched filter       Figure 3   Compress each pulse in range.
%     10 Doppler FFT          Figures 4, 5  Measure speed across pulses.
%     11 CFAR detector        Figure 6   Pick targets out of the noise.
%     12 Tracker              not simulated
%
%   Name-value arguments:
%     save_figures  Write PNG files to output_folder. Default true.
%     show_figures  Show the figure windows. Default true.
%     output_folder Folder for the PNG files. Default "figures" next to this file.
%     seed          Seed for the noise and clutter draws. Default 5.
%     adc_bits      ADC resolution in bits, 2 to 24. Default 12.
%     run_checks    Compare the results with theory. Default true.
%     strict        Error when a check fails. Set false to keep the results and
%                   read results.checks yourself. Default true.
%
%   The scenario parameters come from scenario_parameters_rev1 at the end of
%   this file. They are demo values chosen to make each block easy to see, not
%   values from a fielded radar.
%
%   Example:
%     results = radar_explainer_rev1(show_figures=false);
%     disp(results.detections)

arguments
    opts.save_figures (1,1) logical = true
    opts.show_figures (1,1) logical = true
    opts.output_folder (1,1) string = fullfile(fileparts(mfilename("fullpath")), "figures")
    opts.seed (1,1) double {mustBeInteger, mustBeNonnegative} = 5
    opts.adc_bits (1,1) double {mustBeInteger, mustBeInRange(opts.adc_bits, 2, 24)} = 12
    opts.run_checks (1,1) logical = true
    opts.strict (1,1) logical = true
end

p = scenario_parameters_rev1(opts.adc_bits);
stream = RandStream("mt19937ar", Seed=opts.seed);
vis = "off";
if opts.show_figures
    vis = "on";
end
if opts.save_figures && ~isfolder(opts.output_folder)
    mkdir(opts.output_folder);
end
save_fig = @(fig, name) save_figure_rev1(fig, name, opts);

print_scenario_rev1(p);

% Figure 0: the block diagram that every other figure refers to.
save_fig(plot_block_diagram_rev1(vis), "00_block_diagram.png");

%% Block 1: waveform generator
% The radar transmits a long pulse whose frequency sweeps across a band B. A
% long pulse carries more energy, so the radar sees farther. The sweep gives it
% the bandwidth that sets range resolution. The matched filter later squeezes
% the long pulse into a short one.
[wf, s] = block1_waveform_rev1(p);
save_fig(plot_waveform_rev1(s, p, vis), "01_waveform.png");

%% Scene: what the antenna and RF chain (blocks 2 to 6) deliver
% Blocks 2 to 6 turn the samples into RF, radiate them, and bring the echoes
% back. This code skips that and builds the complex baseband echoes directly:
% two moving targets, a stationary clutter patch, and receiver noise.
x_scene = simulate_scene_rev1(p, s, stream, ["targets" "clutter" "noise"]);
x_targets = simulate_scene_rev1(p, s, stream, "targets");

%% Block 7: ADC
% The ADC turns each I and Q voltage into an integer. More bits give a lower
% quantization noise floor, which matters when strong clutter sets the full scale.
[x_adc, adc] = block7_adc_rev1(x_scene, p.adc_bits);
range_raw = (0:p.num_samples-1).' * p.range_bin_m;
save_fig(plot_raw_echo_rev1(x_adc, range_raw, s, p, vis), "02_received_echo.png");

%% Block 8: digital I/Q
% The samples are already complex baseband (I + jQ), so this block needs no code.

%% Block 9: matched filter
% The matched filter correlates each pulse with the transmit waveform. It is
% the same operation as the sliding-template animation: multiply and sum at
% every delay. The unwindowed filter has the highest SNR. The Taylor-windowed
% filter trades a little SNR and resolution for lower range sidelobes.
[y_plain, y_taylor, coeff] = block9_matched_filter_rev1(wf, x_adc);
[y_plain_targets, y_taylor_targets] = block9_matched_filter_rev1(wf, x_targets(:, 1));
% The matched-filter output at sample n sums the last N input samples, so an
% echo that starts at sample delay+1 peaks at sample delay+N (N = pulse length).
% time2range rejects zero and negative times, so scale the sample index by the
% range-bin size, c/(2*fs), instead.
range_axis = ((1:p.num_samples).' - numel(s)) * p.range_bin_m;
save_fig(plot_matched_filter_rev1(range_axis, y_plain(:, 1), y_taylor(:, 1), ...
    y_plain_targets, y_taylor_targets, p, vis), "03_matched_filter.png");

%% Block 10: Doppler FFT
% A moving target changes the echo phase a little on every pulse. Down the
% pulse (slow-time) dimension, that phase change is a complex sinusoid at the
% Doppler frequency f_d = 2v/lambda. An FFT across pulses turns each sinusoid
% into a peak, and a stationary clutter echo becomes a peak at zero Doppler.
[rd, speed_axis, win] = block10_doppler_fft_rev1(y_taylor, p);
save_fig(plot_slow_time_rev1(y_taylor, rd, range_axis, speed_axis, p, vis), ...
    "04_slow_time_and_doppler.png");
save_fig(plot_range_doppler_rev1(rd, range_axis, speed_axis, p, table(), vis), ...
    "05_range_doppler_map.png");

%% Block 11: CFAR detector
% The CFAR detector sets a threshold in each cell from the average power of
% the cells around it, so the false-alarm rate stays constant as the noise and
% clutter level change.
[detections, num_cells_tested] = block11_cfar_rev1(rd, range_axis, speed_axis, p);
save_fig(plot_range_doppler_rev1(rd, range_axis, speed_axis, p, detections, vis), ...
    "06_cfar_detections.png");

%% Block 12: tracker
% A tracker links detections from scan to scan into tracks. This walkthrough
% stops at detections. See trackerGNN in Sensor Fusion and Tracking Toolbox.

%% Summary and checks
ladder = snr_ladder_rev1(rd, range_axis, speed_axis, win, p);
print_results_rev1(p, adc, detections, num_cells_tested, ladder);

results = struct("params", p, "detections", detections, "snr_ladder", ladder, ...
    "range_axis_m", range_axis, "speed_axis_mps", speed_axis, ...
    "range_doppler", rd, "figure_folder", opts.output_folder, "checks", table());
if opts.run_checks
    results.checks = run_checks_rev1(p, s, coeff, detections, opts.seed);
    print_checks_rev1(results.checks);
    if opts.strict && ~all(results.checks.passed)
        error("radar_explainer:checkFailed", ...
            "A theory check failed. See the check table above.");
    end
end
end

%% Scenario

function p = scenario_parameters_rev1(adc_bits)
%SCENARIO_PARAMETERS_REV1 Demo scenario. Change values here to experiment.
p.fc = 2.7e9;                       % Carrier frequency (Hz).
p.bandwidth = 5e6;                  % Chirp bandwidth B (Hz).
p.pulse_width = 10e-6;              % Pulse length (s).
p.fs = 20e6;                        % ADC sample rate (Hz), 4 samples per 1/B.
p.prf = 2e3;                        % Pulse repetition frequency (Hz).
p.num_pulses = 64;                  % Pulses in one coherent dwell.
p.max_range = 15e3;                 % Receive window length (m).
p.adc_bits = adc_bits;              % ADC resolution (bits).
p.target_range_m = [12000; 12030];  % Target 2 is one range cell behind target 1.
p.target_speed_mps = [30; -20];     % Positive speed is toward the radar.
p.target_snr_db = [-10; -13];       % Per-sample SNR before any processing.
p.clutter_range_m = [11800 12300];  % Stationary clutter patch (m).
p.clutter_cnr_db = 25;              % Per-sample clutter-to-noise ratio (dB).
p.pfa = 1e-6;                       % CFAR probability of false alarm per cell.
p.c = physconst("LightSpeed");
p.lambda = freq2wavelen(p.fc, p.c);
p.pri = 1 / p.prf;
p.num_samples = round(range2time(p.max_range, p.c) * p.fs);
p.range_bin_m = time2range(1 / p.fs, p.c);
p.unambiguous_range_m = time2range(p.pri, p.c);
% speed2dop and dop2speed use the one-way Doppler shift, v/lambda. A radar
% sees the two-way shift, 2v/lambda, so the speed is half of dop2speed.
p.speed_bin_mps = dop2speed(p.prf / p.num_pulses, p.lambda) / 2;
p.unambiguous_speed_mps = dop2speed(p.prf / 2, p.lambda) / 2;
end

%% Blocks

function [wf, s] = block1_waveform_rev1(p)
%BLOCK1_WAVEFORM_REV1 Linear FM chirp, centered on zero frequency at baseband.
wf = phased.LinearFMWaveform(SampleRate=p.fs, PulseWidth=p.pulse_width, ...
    PRF=p.prf, SweepBandwidth=p.bandwidth, SweepDirection="Up", ...
    SweepInterval="Symmetric");
% The object returns one full pulse repetition interval (PRI), which is the
% pulse followed by zeros. Keep only the pulse itself.
s = wf();
s = s(1:round(p.pulse_width * p.fs));
end

function x = simulate_scene_rev1(p, s, stream, parts)
%SIMULATE_SCENE_REV1 Complex baseband echoes, one column per pulse.
%   parts selects any of "targets", "clutter", "noise". Noise has unit variance.
n_pulse = p.num_pulses;
len = numel(s);
x = zeros(p.num_samples, n_pulse);
pulse_index = 0:n_pulse-1;

if any(parts == "targets")
    for k = 1:numel(p.target_range_m)
        delay = round(range2time(p.target_range_m(k), p.c) * p.fs);
        amplitude = 10^(p.target_snr_db(k) / 20);
        doppler_hz = 2 * speed2dop(p.target_speed_mps(k), p.lambda);   % Two-way shift.
        carrier_phase = -2 * pi * p.fc * range2time(p.target_range_m(k), p.c);
        % The echo phase advances by 2*pi*f_d*PRI on every pulse. This model
        % ignores range migration: the targets move about 1 m during the dwell,
        % which is less than one 7.5 m range cell.
        pulse_phase = exp(1j * (carrier_phase + 2*pi*doppler_hz*p.pri*pulse_index));
        samples = delay + (1:len);
        x(samples, :) = x(samples, :) + amplitude * s * pulse_phase;
    end
end

if any(parts == "clutter")
    first_cell = round(range2time(p.clutter_range_m(1), p.c) * p.fs) + 1;
    last_cell = round(range2time(p.clutter_range_m(2), p.c) * p.fs);
    cells = first_cell:last_cell;
    % Each range cell reflects with a random complex amplitude. The echo from
    % a cell is a copy of the pulse, so the clutter is the cell amplitudes
    % convolved with the pulse. The same echo returns on every pulse, which
    % makes the clutter stationary (zero Doppler).
    sigma_cell = sqrt(10^(p.clutter_cnr_db / 10) / len);
    cell_amplitude = zeros(p.num_samples, 1);
    cell_amplitude(cells) = sigma_cell / sqrt(2) * ...
        (randn(stream, numel(cells), 1) + 1j * randn(stream, numel(cells), 1));
    echo = conv(cell_amplitude, s);
    x = x + echo(1:p.num_samples);
end

if any(parts == "noise")
    x = x + (randn(stream, p.num_samples, n_pulse) + ...
        1j * randn(stream, p.num_samples, n_pulse)) / sqrt(2);
end
end

function [xq, info] = block7_adc_rev1(x, n_bits)
%BLOCK7_ADC_REV1 Mid-tread quantizer on I and Q, full scale set by the peak.
% Considered: quantiz (Communications Toolbox) and dsp.ScalarQuantizerEncoder.
% Both need a partition and codebook or return indices, so two lines of custom
% rounding show the ADC more directly.
info.full_scale = 1.05 * max(abs([real(x(:)); imag(x(:))]));
info.step = 2 * info.full_scale / 2^n_bits;
info.noise_power = info.step^2 / 6;     % Two components at step^2/12 each.
xq = info.step * complex(round(real(x) / info.step), round(imag(x) / info.step));
end

function [y_plain, y_taylor, coeff] = block9_matched_filter_rev1(wf, x)
%BLOCK9_MATCHED_FILTER_REV1 Correlate each pulse with the transmit chirp.
coeff = getMatchedFilter(wf);
% For a linear FM chirp, weighting the reference in time is the same as
% weighting its spectrum across the swept band. The built-in SpectrumWindow
% option tapers across the whole sampled band instead (20 MHz here, while the
% chirp fills 5 MHz), which costs about 13 dB of peak and blurs the range.
coeff_taylor = coeff .* taylorwin(numel(coeff), 4, -40);
mf_plain = phased.MatchedFilter(Coefficients=coeff);
mf_taylor = phased.MatchedFilter(Coefficients=coeff_taylor);
y_plain = mf_plain(x);
y_taylor = mf_taylor(x);
end

function [rd, speed_axis, win] = block10_doppler_fft_rev1(y, p)
%BLOCK10_DOPPLER_FFT_REV1 Windowed FFT across pulses (slow time) in every range bin.
win = taylorwin(p.num_pulses, 4, -50);
rd = fftshift(fft(y .* win.', [], 2), 2);
doppler_axis = (-p.num_pulses/2 : p.num_pulses/2 - 1).' * p.prf / p.num_pulses;
speed_axis = dop2speed(doppler_axis, p.lambda) / 2;   % Two-way shift to speed.
end

function [detections, num_cells_tested] = block11_cfar_rev1(rd, range_axis, speed_axis, p)
%BLOCK11_CFAR_REV1 Cell-averaging CFAR on the range-Doppler power map.
power_map = abs(rd).^2;
guard = [4 3];      % Cells skipped on each side of the cell under test (range, Doppler).
train = [10 4];     % Cells averaged on each side (range, Doppler).
cfar = phased.CFARDetector2D(Method="CA", GuardBandSize=guard, ...
    TrainingBandSize=train, ProbabilityFalseAlarm=p.pfa, ThresholdOutputPort=true);
margin = guard + train;
rows = find(range_axis >= 11.4e3 & range_axis <= 12.6e3);
rows = rows(rows > margin(1) & rows <= size(power_map, 1) - margin(1));
cols = (margin(2) + 1) : (size(power_map, 2) - margin(2));
% Skip the clutter ridge at zero Doppler. A fielded radar also filters
% stationary clutter before detection, for example with a Doppler notch.
cols = cols(abs(speed_axis(cols)) > 3 * p.speed_bin_mps);
[row_grid, col_grid] = ndgrid(rows, cols);
cell_index = [row_grid(:).'; col_grid(:).'];
num_cells_tested = size(cell_index, 2);
hit = cfar(power_map, cell_index);
detected = false(size(power_map));
detected(sub2ind(size(power_map), cell_index(1, hit(:)), cell_index(2, hit(:)))) = true;
% Keep only the strongest cell in each 3-by-3 neighborhood, so one target gives
% one detection. Considered: imregionalmax (Image Processing Toolbox is not
% installed); movmax is in base MATLAB.
local_max = power_map == movmax(movmax(power_map, 3, 1), 3, 2);
[r, c] = find(detected & local_max);
linear = sub2ind(size(power_map), r, c);
[~, order] = sort(power_map(linear), "descend");
r = r(order);
c = c(order);
detections = table(range_axis(r), speed_axis(c), ...
    10*log10(power_map(sub2ind(size(power_map), r, c))), ...
    VariableNames=["range_m" "speed_mps" "power_db"]);
end

%% Summary helpers

function ladder = snr_ladder_rev1(rd, range_axis, speed_axis, win, p)
%SNR_LADDER_REV1 SNR of target 1 at each stage, in dB.
len = round(p.pulse_width * p.fs);
quiet = range_axis >= 12.8e3 & range_axis <= 13.4e3;   % No targets or clutter here.
% The median is robust to range sidelobes of the clutter ridge. Dividing by
% log(2) converts the median of exponentially distributed noise power to its mean.
floor_power = median(abs(rd(quiet, :)).^2, "all") / log(2);
[~, row] = min(abs(range_axis - p.target_range_m(1)));
[~, col] = min(abs(speed_axis - p.target_speed_mps(1)));
% Clamp the neighborhood so a target at the edge of the Doppler axis (for
% example, an aliased speed) doesn't index past the array.
near_rows = max(row - 1, 1) : min(row + 1, size(rd, 1));
near_cols = max(col - 1, 1) : min(col + 1, size(rd, 2));
peak_power = max(abs(rd(near_rows, near_cols)).^2, [], "all");
ladder.input_db = p.target_snr_db(1);
ladder.after_matched_filter_db = p.target_snr_db(1) + 10*log10(len);
ladder.after_doppler_fft_db = 10*log10(peak_power / floor_power);
ladder.doppler_gain_theory_db = 10*log10(sum(win)^2 / sum(win.^2));
end

function print_scenario_rev1(p)
fprintf("\nScenario\n");
fprintf("  Carrier %.2f GHz, wavelength %.1f cm\n", p.fc/1e9, 100*p.lambda);
fprintf("  Chirp: %.0f MHz bandwidth, %.0f microseconds long, time-bandwidth product %.0f\n", ...
    p.bandwidth/1e6, p.pulse_width*1e6, p.pulse_width*p.bandwidth);
fprintf("  Range resolution c/(2B) = %.0f m; range cell (sample) = %.2f m\n", ...
    bw2rangeres(p.bandwidth, p.c), time2range(1/p.fs, p.c));
fprintf("  PRF %.0f Hz: unambiguous range %.0f km, unambiguous speed +/-%.1f m/s\n", ...
    p.prf, p.unambiguous_range_m/1e3, p.unambiguous_speed_mps);
fprintf("  Dwell %d pulses: speed bin %.2f m/s\n", p.num_pulses, p.speed_bin_mps);
end

function print_results_rev1(p, adc, detections, num_cells_tested, ladder)
fprintf("\nADC: %d bits, quantization noise %.1e (receiver noise is 1)\n", ...
    p.adc_bits, adc.noise_power);
fprintf("\nSNR of target 1 at each stage\n");
fprintf("  Per sample, before processing:   %6.1f dB\n", ladder.input_db);
fprintf("  After matched filter (theory):   %6.1f dB  (+%.1f dB = 10log10(N))\n", ...
    ladder.after_matched_filter_db, ladder.after_matched_filter_db - ladder.input_db);
fprintf("  After Doppler FFT (measured):    %6.1f dB  (Doppler window gain in theory %.1f dB)\n", ...
    ladder.after_doppler_fft_db, ladder.doppler_gain_theory_db);
fprintf("\nCFAR tested %d cells and reported %d detections\n", ...
    num_cells_tested, height(detections));
disp(detections);
fprintf("Truth: range %s m, speed %s m/s\n", ...
    mat2str(p.target_range_m.'), mat2str(p.target_speed_mps.'));
end

function print_checks_rev1(checks)
fprintf("\nChecks against theory\n");
for k = 1:height(checks)
    status = "PASS";
    if ~checks.passed(k)
        status = "FAIL";
    end
    fprintf("  %s  %s: measured %.3g, expected %.3g\n", status, ...
        checks.name(k), checks.measured(k), checks.expected(k));
end
end

%% Checks

function checks = run_checks_rev1(p, s, coeff, detections, seed)
%RUN_CHECKS_REV1 Compare the pipeline with closed-form results.
len = numel(s);
stream = RandStream("mt19937ar", Seed=seed + 1000);
mf = phased.MatchedFilter(Coefficients=coeff);

% A unit-amplitude echo and unit-variance noise give 0 dB SNR per sample, so
% the output SNR in dB is the matched-filter gain, which theory puts at 10log10(N).
echo_start = 100;
x_echo = zeros(p.num_samples, 1);
x_echo(echo_start + (1:len)) = s;
y_echo = mf(x_echo);
[peak, peak_index] = max(abs(y_echo));
mf_noise = phased.MatchedFilter(Coefficients=coeff);
x_noise = (randn(stream, p.num_samples, p.num_pulses) + ...
    1j * randn(stream, p.num_samples, p.num_pulses)) / sqrt(2);
y_noise = mf_noise(x_noise);
noise_power = mean(abs(y_noise(len:end, :)).^2, "all");
gain_db = 10*log10(peak^2 / noise_power);

% The -3 dB width of the compressed pulse is about 0.886 c/(2B) for a chirp
% with a large time-bandwidth product. Interpolate because the sample spacing
% (7.5 m) is coarse compared with the width.
half_span = 8;
segment = abs(y_echo(peak_index + (-half_span:half_span))) / peak;
fine_axis = linspace(-half_span, half_span, 1601);
fine_segment = interp1(-half_span:half_span, segment, fine_axis, "pchip");
above = fine_axis(fine_segment >= 1/sqrt(2));
width_m = (max(above) - min(above)) * time2range(1/p.fs, p.c);
width_expected_m = 0.886 * bw2rangeres(p.bandwidth, p.c);

num_targets = numel(p.target_range_m);
found = false(num_targets, 1);
for k = 1:num_targets
    near_range = abs(detections.range_m - p.target_range_m(k)) <= p.range_bin_m;
    near_speed = abs(detections.speed_mps - p.target_speed_mps(k)) <= p.speed_bin_mps;
    found(k) = any(near_range & near_speed);
end
num_false = height(detections) - nnz(found);

name = ["Matched-filter SNR gain (dB)"; "Compressed-pulse peak sample"; ...
    "Compressed-pulse -3 dB width (m)"; "Targets detected"; "False alarms"];
measured = [gain_db; peak_index; width_m; nnz(found); num_false];
expected = [10*log10(len); echo_start + len; width_expected_m; num_targets; 0];
tolerance = [0.5; 0; 0.1*width_expected_m; 0; 0];
passed = abs(measured - expected) <= tolerance;
checks = table(name, measured, expected, passed);
end

%% Figures

function save_figure_rev1(fig, name, opts)
if opts.save_figures
    exportgraphics(fig, fullfile(opts.output_folder, name), Resolution=150);
end
if ~opts.show_figures
    close(fig);
end
end

function fig = new_figure_rev1(vis, position)
fig = figure(Visible=vis, Color="w", Position=position);
% Force the light theme so the saved figures look the same on every machine,
% including MATLAB sessions that follow a dark system theme.
theme(fig, "light");
end

function fig = plot_block_diagram_rev1(vis)
%PLOT_BLOCK_DIAGRAM_REV1 Draw the radar block diagram. Figure 0.
arguments
    vis (1,1) string = "on"
end
fig = new_figure_rev1(vis, [100 100 1000 560]);
ax = axes(fig, "Position", [0.02 0.02 0.96 0.96]);
hold(ax, "on");
axis(ax, [0 100 -4 68]);
axis(ax, "off");

names = ["Waveform gen" "DAC" "Upconvert + PA" "Antenna" "LNA" "Downconvert" ...
    "ADC" "Digital I/Q" "Matched filter" "Doppler FFT" "CFAR" "Tracker"];
notes = ["Figure 1" "ideal" "ideal" "ideal" "ideal" "ideal" "Figure 2" "ideal" ...
    "Figure 3" "Figures 4, 5" "Figure 6" "not simulated"];
kind = ["digital" "convert" "analog" "analog" "analog" "analog" "convert" ...
    "digital" "digital" "digital" "digital" "digital"];
simulated = logical([1 0 0 0 0 0 1 0 1 1 1 0]);
colors = struct("analog", [0.98 0.86 0.81], "convert", [0.89 0.89 0.87], ...
    "digital", [0.81 0.93 0.90]);
box_w = 20;
box_h = 11;
col_x = [5 29 53 77];
row_y = [48 26 4];

corner = zeros(12, 2);
for k = 1:12
    row = floor((k - 1) / 4);
    col = mod(k - 1, 4);
    if row == 1
        col = 3 - col;      % The receive row runs right to left.
    end
    corner(k, :) = [col_x(col + 1), row_y(row + 1)];
    line_style = "-";
    if ~simulated(k)
        line_style = "--";
    end
    rectangle(ax, "Position", [corner(k, :) box_w box_h], "Curvature", 0.15, ...
        "FaceColor", colors.(kind(k)), "EdgeColor", [0.25 0.25 0.25], ...
        "LineStyle", line_style, "LineWidth", 1.5);
    text(ax, corner(k, 1) + box_w/2, corner(k, 2) + 0.64*box_h, ...
        sprintf("%d  %s", k, names(k)), "HorizontalAlignment", "center", ...
        "FontSize", 11, "FontWeight", "bold");
    text(ax, corner(k, 1) + box_w/2, corner(k, 2) + 0.27*box_h, notes(k), ...
        "HorizontalAlignment", "center", "FontSize", 10, "Color", [0.3 0.3 0.3]);
end

gap = 0.5;
x0 = zeros(11, 1); y0 = x0; dx = x0; dy = x0;
for k = 1:11
    here = corner(k, :);
    there = corner(k + 1, :);
    if here(2) == there(2)      % Same row: horizontal arrow.
        direction = sign(there(1) - here(1));
        edge_here = here(1) + box_w * (direction > 0);
        edge_there = there(1) + box_w * (direction < 0);
        x0(k) = edge_here + direction * gap;
        y0(k) = here(2) + box_h / 2;
        dx(k) = edge_there - direction * gap - x0(k);
    else                        % Next row: vertical arrow.
        x0(k) = here(1) + box_w / 2;
        y0(k) = here(2) - gap;
        dy(k) = there(2) + box_h + gap - y0(k);
    end
end
quiver(ax, x0, y0, dx, dy, 0, "Color", [0.15 0.15 0.15], "LineWidth", 1.4, ...
    "MaxHeadSize", 0.9);

text(ax, 50, 65, "Digital pulse-Doppler radar: transmit on top, receive and processing below", ...
    "HorizontalAlignment", "center", "FontSize", 13, "FontWeight", "bold");
legend_x = [5 29 53];
legend_labels = ["Analog RF" "Converter" "Digital"];
legend_colors = [colors.analog; colors.convert; colors.digital];
for k = 1:3
    rectangle(ax, "Position", [legend_x(k) -2.5 3 2.5], "FaceColor", legend_colors(k, :), ...
        "EdgeColor", [0.25 0.25 0.25]);
    text(ax, legend_x(k) + 4, -1.25, legend_labels(k), "FontSize", 10);
end
text(ax, 72, -1.25, "Solid: simulated. Dashed: ideal.", ...
    "FontSize", 10, "HorizontalAlignment", "left");
end

function fig = plot_waveform_rev1(s, p, vis)
%PLOT_WAVEFORM_REV1 Figure 1: the transmit chirp in time and frequency.
fig = new_figure_rev1(vis, [100 100 900 620]);
tl = tiledlayout(fig, 2, 1, "TileSpacing", "compact");
title(tl, "Figure 1. Block 1: the transmit chirp");
nexttile(tl);
t_us = (0:numel(s)-1).' / p.fs * 1e6;
plot(t_us, real(s), t_us, imag(s), "LineWidth", 1.2);
grid on;
xlabel("Time (microseconds)");
ylabel("Amplitude");
legend("Real (I)", "Imaginary (Q)", "Location", "northeast");
title(sprintf("The frequency sweeps from %.1f to +%.1f MHz over %.0f microseconds,\n" + ...
    "so the oscillation slows to zero at the midpoint", ...
    -p.bandwidth/2e6, p.bandwidth/2e6, p.pulse_width*1e6));
nexttile(tl);
[pxx, f] = periodogram(s, [], 4096, p.fs, "centered");
plot(f/1e6, 10*log10(pxx / max(pxx)), "LineWidth", 1.2);
grid on;
xlim([-10 10]);
ylim([-60 5]);
xlabel("Frequency (MHz)");
ylabel("Power (dB re peak)");
title(sprintf("The sweep fills B = %.0f MHz, so range resolution is c/(2B) = %.0f m", ...
    p.bandwidth/1e6, bw2rangeres(p.bandwidth, p.c)));
end

function fig = plot_raw_echo_rev1(x, range_raw, s, p, vis)
%PLOT_RAW_ECHO_REV1 Figure 2: one received pulse after the ADC.
fig = new_figure_rev1(vis, [100 100 900 480]);
plot(range_raw/1e3, 10*log10(abs(x(:, 1)).^2), "LineWidth", 1);
grid on;
hold on;
xline(mean(p.target_range_m)/1e3, "r--", "Both targets", ...
    "LabelVerticalAlignment", "bottom", "LineWidth", 1.2);
xlabel("Range (km)");
ylabel("Power per sample (dB re noise)");
patch_end = p.clutter_range_m(2) + time2range(numel(s)/p.fs, p.c);
title(sprintf("Figure 2. Block 7: one pulse after the ADC. A %.1f km pulse smears each echo,\n" + ...
    "and the targets sit inside the clutter patch (%.1f to %.1f km)", ...
    time2range(numel(s)/p.fs, p.c)/1e3, p.clutter_range_m(1)/1e3, patch_end/1e3));
end

function fig = plot_matched_filter_rev1(range_axis, y_plain, y_taylor, ...
    y_plain_tgt, y_taylor_tgt, p, vis)
%PLOT_MATCHED_FILTER_REV1 Figure 3: matched-filter output, with and without clutter.
fig = new_figure_rev1(vis, [100 100 900 680]);
tl = tiledlayout(fig, 2, 1, "TileSpacing", "compact");
title(tl, "Figure 3. Block 9: the matched filter compresses the pulse");
zoom = range_axis >= 11.5e3 & range_axis <= 12.5e3;
r_km = range_axis(zoom) / 1e3;

nexttile(tl);
plot(r_km, 10*log10(abs(y_plain(zoom)).^2), r_km, 10*log10(abs(y_taylor(zoom)).^2), ...
    "LineWidth", 1.2);
grid on;
xline(p.target_range_m/1e3, "k:");
ylabel("Power (dB)");
legend("No window", "Taylor window", "Location", "northeast");
title("One pulse with clutter and noise: clutter hides the targets");

nexttile(tl);
floor_db = -60;
plain_db = 10*log10(abs(y_plain_tgt(zoom)).^2 / max(abs(y_plain_tgt).^2));
taylor_db = 10*log10(abs(y_taylor_tgt(zoom)).^2 / max(abs(y_plain_tgt).^2));
plot(r_km, max(plain_db, floor_db), r_km, max(taylor_db, floor_db), "LineWidth", 1.2);
grid on;
xline(p.target_range_m/1e3, "k:");
ylim([floor_db 5]);
xlabel("Range (km)");
ylabel("Power (dB re peak)");
legend("No window", "Taylor window", "Location", "northeast");
title(sprintf("Targets only: the two targets, %.0f m apart, merge into one peak.\n" + ...
    "The window lowers the sidelobes and widens the peak.", ...
    diff(p.target_range_m)));
end

function fig = plot_slow_time_rev1(y, rd, range_axis, speed_axis, p, vis)
%PLOT_SLOW_TIME_REV1 Figure 4: one range bin across pulses, then its spectrum.
fig = new_figure_rev1(vis, [100 100 900 820]);
tl = tiledlayout(fig, 3, 1, "TileSpacing", "compact");
title(tl, "Figure 4. Block 10: the Doppler FFT turns phase change into speed");
[~, row] = min(abs(range_axis - p.target_range_m(1)));
samples = real(y(row, :));
pulse = 1:p.num_pulses;

nexttile(tl);
plot(pulse, samples, "-o", "LineWidth", 1, "MarkerSize", 4);
grid on;
ylabel("Real part");
title(sprintf("Range bin at %.2f km, as measured: the clutter is a large steady offset", ...
    range_axis(row)/1e3));

nexttile(tl);
plot(pulse, samples - mean(samples), "-o", "LineWidth", 1, "MarkerSize", 4);
grid on;
xlabel("Pulse number (slow time)");
ylabel("Real part");
title("With the average removed, the ripple left is the moving target");

nexttile(tl);
plot(speed_axis, 10*log10(abs(rd(row, :)).^2), "LineWidth", 1.2);
grid on;
xline(p.target_speed_mps, "r--", ["Target 1" "Target 2"], "LabelVerticalAlignment", "bottom");
xlabel("Speed (m/s, positive toward radar)");
ylabel("Power (dB)");
title("FFT across the pulses: clutter at 0 m/s, each target at its own speed");
end

function fig = plot_range_doppler_rev1(rd, range_axis, speed_axis, p, detections, vis)
%PLOT_RANGE_DOPPLER_REV1 Figures 5 and 6: range-Doppler map, with CFAR detections if given.
fig = new_figure_rev1(vis, [100 100 900 600]);
rows = range_axis >= 11.7e3 & range_axis <= 12.4e3;
map_db = 10*log10(abs(rd(rows, :)).^2);
imagesc(speed_axis, range_axis(rows)/1e3, map_db);
axis xy;
colormap(gca, turbo);
cb = colorbar;
cb.Label.String = "Power (dB)";
noise_db = median(map_db(:));
% Set the top of the color scale from the strongest cell away from zero Doppler,
% so the clutter ridge saturates and the targets stay visible.
away = abs(speed_axis) > 3 * p.speed_bin_mps;
clim([noise_db, max(map_db(:, away), [], "all") + 3]);
hold on;
plot(p.target_speed_mps, p.target_range_m/1e3, "wo", "MarkerSize", 14, "LineWidth", 1.5);
xlabel("Speed (m/s, positive toward radar)");
ylabel("Range (km)");
if isempty(detections)
    title(sprintf("Figure 5. Block 10: range-Doppler map. Clutter is the vertical ridge at 0 m/s.\n" + ...
        "White circles mark the true targets (speed %d and %d m/s)", p.target_speed_mps));
else
    plot(detections.speed_mps, detections.range_m/1e3, "rx", "MarkerSize", 12, "LineWidth", 2);
    title(sprintf("Figure 6. Block 11: CFAR detections (red x) at the true targets (white circles).\n" + ...
        "%d detections, threshold set for Pfa = %.0e per cell", height(detections), p.pfa));
end
end
