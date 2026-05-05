function result = HDSP_sonoink_fullflow_validation(varargin)
% HDSP_SONOINK_FULLFLOW_VALIDATION
% Dedicated full-flow validation for cure system #3: self-enhancing sonoink.
%
% This script keeps the HDSP acoustic chain intact:
%   target -> Python initial phase -> Python+IASA phase -> phase board
%   -> k-Wave propagation through board + sonoink medium -> sonoink cure model.
%
% Default usage:
%   result = HDSP_sonoink_fullflow_validation();
%
% Fast structural check:
%   result = HDSP_sonoink_fullflow_validation('dry_run', true);

opts = parse_options(varargin{:});
script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(script_dir);
addpath(script_dir);
addpath(repo_root);
if ~isempty(opts.external_hdsp_path) && exist(opts.external_hdsp_path, 'dir')
    addpath(opts.external_hdsp_path);
end

try
    reset(gpuDevice);
catch
end
rng(9426);

%% 1. System parameters
Nx = 512;
Ny = Nx;
Lx = 65e-3;
z_target_dist = 16e-3;
f0 = 4.5e6;

c_water = 1480;
density_water = 997;
alpha_coeff_water = 0.002;
alpha_power_water = 1.5;

c_board = 2430;
density_board = 1100;
alpha_coeff_board = 1.5;

% Water-rich sonoink approximation. The cure model, not this acoustic
% approximation, carries the self-enhancing absorption / gelation behavior.
c_sonoink = 1500;
density_sonoink = 1010;
alpha_coeff_sonoink = 0.35;

phase_refine_mode = 'python_iasa';
iasa_epoch = 150;
iasa_anchor_eta = 1.0;
min_base_layers = 2;
focus_scan_radius = 3.5e-3;
focus_edge_warn_mm = 0.5;

dx = Lx / Nx;
dy = dx;
dz = dx;
lambda_water = c_water / f0;
Lz_needed = 20e-3;
Nz_min = ceil(Lz_needed / dz);
optimal_sizes = [128, 192, 216, 256, 300, 384, 512];
Nz = optimal_sizes(find(optimal_sizes >= Nz_min, 1));
Lz = Nz * dz;
x = (-Nx/2:Nx/2-1) * dx;
y = x;

cure_params = build_cure_system_profile('sonoink_self_enhancing', dx);
cure_params.threshold = 1.0;
cure_params.spatial_dx = dx;

fprintf('==================================================\n');
fprintf('Sonoink full-flow validation\n');
fprintf('Grid: %d x %d x %d | dx %.2f um | PPW %.2f\n', ...
    Nx, Ny, Nz, dx * 1e6, lambda_water / dx);
fprintf('Acoustic medium: board + water-rich sonoink region\n');
fprintf('Cure model: %s (%s)\n', cure_params.model_name, cure_params.cure_mechanism);
fprintf('==================================================\n');

%% 2. Target pattern and transport export
[imag_target, imag_target_design, imag_target_raw, X_grid, Y_grid] = ...
    build_scaffold_target(x, y, dx);
target_mask = imag_target > 0.5;
ROI_pixels = nnz(target_mask);
fprintf('Target ROI pixels: %d\n', ROI_pixels);

if ~exist(opts.transport_dir, 'dir')
    mkdir(opts.transport_dir);
end
export_path = fullfile(opts.transport_dir, 'target_for_python.mat');
thermal_sigma_px = 0.8;
save(export_path, 'imag_target', 'imag_target_design', 'Nx', 'Ny', 'Lx', ...
    'lambda_water', 'z_target_dist', 'dx', 'dz', 'f0', 'c_water', ...
    'c_board', 'density_water', 'density_board', 'alpha_coeff_water', ...
    'thermal_sigma_px', 'min_base_layers');
fprintf('Python phase target exported to: %s\n', export_path);

result = struct();
result.status = 'target_exported';
result.export_path = export_path;
result.cure_params = cure_params;
result.grid = struct('Nx', Nx, 'Ny', Ny, 'Nz', Nz, 'dx', dx, 'dy', dy, 'dz', dz);

if opts.dry_run
    result.status = 'dry_run_complete';
    fprintf('Dry run complete. k-Wave and cure scan were skipped.\n');
    return;
end

import_path = fullfile(opts.transport_dir, 'dl_phase_init.mat');
if ~exist(import_path, 'file')
    error('HDSP_sonoink:MissingPythonPhase', ...
        ['Missing dl_phase_init.mat. Run the Python phase-generation step ', ...
        'after reading %s.'], export_path);
end

%% 3. Python initialized IASA
load(import_path, 'optimal_initial_phase', 'optimal_phase_bias', ...
    'target_dose_design', 'line_target_mask', 'halo_target_mask');

[holo_phase, net_num_board, phase_step, asm_iasa_norm, asm_metrics, circle_mask_board] = ...
    build_python_iasa_board_phase(optimal_initial_phase, optimal_phase_bias, ...
    target_dose_design, line_target_mask, halo_target_mask, imag_target, ...
    X_grid, Y_grid, Nx, Ny, Lx, z_target_dist, f0, c_water, c_board, ...
    dz, min_base_layers, iasa_epoch, iasa_anchor_eta, phase_refine_mode);

%% 4. k-Wave through phase board + sonoink region
kwave_result = run_board_sonoink_kwave(holo_phase, net_num_board, circle_mask_board, ...
    imag_target, Nx, Ny, Nz, dx, dy, dz, Lz, z_target_dist, focus_scan_radius, ...
    focus_edge_warn_mm, f0, c_water, density_water, alpha_coeff_water, ...
    alpha_power_water, c_board, density_board, alpha_coeff_board, ...
    c_sonoink, density_sonoink, alpha_coeff_sonoink);
kwave_metrics = calc_image_metrics(kwave_result.p_focal_norm, imag_target);
asm_kwave_corr = corr2(asm_iasa_norm, kwave_result.p_focal_norm);
asm_kwave_nmse = sum((asm_iasa_norm(:) - kwave_result.p_focal_norm(:)).^2) ...
    / (sum(asm_iasa_norm(:).^2) + eps);

%% 5. Sonoink cure scan on the simulated focal pressure
cure_result = run_sonoink_cure_scan(kwave_result.p_focal_amp, target_mask, ...
    cure_params, opts.pressure_scan, opts.exposure_scan);

%% 6. Export
out_dir = opts.output_dir;
if isempty(out_dir)
    out_dir = fullfile(fileparts(mfilename('fullpath')), 'outputs');
end
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

fig_path = fullfile(out_dir, 'sonoink_fullflow_overview.png');
export_overview_figure(fig_path, x, y, imag_target, holo_phase, ...
    kwave_result, cure_result, asm_iasa_norm, asm_metrics, kwave_metrics, ...
    asm_kwave_corr);

mat_path = fullfile(out_dir, 'sonoink_fullflow_validation.mat');
save(mat_path, 'imag_target', 'imag_target_design', 'imag_target_raw', ...
    'holo_phase', 'net_num_board', 'phase_step', 'asm_iasa_norm', ...
    'asm_metrics', 'kwave_result', 'kwave_metrics', 'asm_kwave_corr', ...
    'asm_kwave_nmse', 'cure_result', 'cure_params', 'c_sonoink', ...
    'density_sonoink', 'alpha_coeff_sonoink', 'dx', 'dy', 'dz', ...
    'f0', 'z_target_dist', '-v7.3');

result.status = 'complete';
result.output_dir = out_dir;
result.figure_path = fig_path;
result.mat_path = mat_path;
result.asm_metrics = asm_metrics;
result.kwave_metrics = kwave_metrics;
result.asm_kwave_corr = asm_kwave_corr;
result.asm_kwave_nmse = asm_kwave_nmse;
result.cure_result = cure_result;
result.kwave_result = kwave_result;

print_summary(cure_result, asm_metrics, kwave_metrics, kwave_result, ...
    asm_kwave_corr, asm_kwave_nmse, out_dir, cure_params);

try
    reset(gpuDevice);
catch
end
end

function opts = parse_options(varargin)
parser = inputParser;
parser.addParameter('dry_run', false, @(x) islogical(x) || isnumeric(x));
parser.addParameter('transport_dir', 'C:\Users\Zh89\Desktop\transport', @ischar);
parser.addParameter('output_dir', '', @ischar);
parser.addParameter('external_hdsp_path', '', @ischar);
parser.addParameter('pressure_scan', (0.6:0.1:2.6) * 1e6, @isnumeric);
parser.addParameter('exposure_scan', 0.10:0.05:1.20, @isnumeric);
parser.parse(varargin{:});
opts = parser.Results;
opts.dry_run = logical(opts.dry_run);
end

function [imag_target, imag_target_design, imag_target_raw, X_grid, Y_grid] = ...
    build_scaffold_target(x, y, dx)
[Y_grid, X_grid] = meshgrid(y, x);
strut_width = 1.0e-3;
pore_size = 3.0e-3;
pitch = strut_width + pore_size;
mask_X = mod(X_grid + pitch / 2, pitch) < strut_width;
mask_Y = mod(Y_grid + pitch / 2, pitch) < strut_width;
scaffold_raw = mask_X | mask_Y;

target_radius = 15e-3;
circle_mask = (X_grid.^2 + Y_grid.^2) <= target_radius^2;
imag_target_raw = scaffold_raw & circle_mask;
imag_target = imgaussfilt(double(imag_target_raw), 0.5);
imag_target = imag_target / max(imag_target(:));

thermal_alpha_guess = 0.15 / (1100 * 1800);
thermal_exposure_guess = 0.35;
thermal_diff_len = sqrt(4 * thermal_alpha_guess * thermal_exposure_guess);
thermal_sigma_px = max(0.8, 0.35 * thermal_diff_len / dx);
precomp_threshold = 0.58;
design_blur = imgaussfilt(double(imag_target_raw), thermal_sigma_px);
imag_target_design = double(design_blur > precomp_threshold);
imag_target_design = imgaussfilt(imag_target_design, 0.45);
imag_target_design = imag_target_design / max(imag_target_design(:));
end

function [holo_phase, net_num_board, phase_step, asm_iasa_norm, asm_metrics, circle_mask_board] = ...
    build_python_iasa_board_phase(optimal_initial_phase, optimal_phase_bias, ...
    target_dose_design, line_target_mask, halo_target_mask, imag_target, ...
    X_grid, Y_grid, Nx, Ny, Lx, z_target_dist, f0, c_water, c_board, ...
    dz, min_base_layers, iasa_epoch, iasa_anchor_eta, phase_refine_mode)

pad_factor = 2;
Nx_pad = Nx * pad_factor;
Ny_pad = Ny * pad_factor;
Lx_pad = Lx * pad_factor;
dk_pad = 2 * pi / Lx_pad;
kx_pad = (-Nx_pad/2:Nx_pad/2-1) * dk_pad;
[Kx_pad, Ky_pad] = meshgrid(kx_pad, kx_pad);
lambda_water = c_water / f0;
k_water = 2 * pi / lambda_water;
Kz_sq = k_water^2 - Kx_pad.^2 - Ky_pad.^2;
propagating = (Kz_sq > 0);
Kz = zeros(size(Kz_sq));
Kz(propagating) = sqrt(Kz_sq(propagating));
H_forward = zeros(size(Kz_sq));
H_forward(propagating) = exp(1i * Kz(propagating) * z_target_dist);
H_backward = conj(H_forward);

center_idx = Nx/2+1:Nx/2+Nx;
target_pad = zeros(Nx_pad, Ny_pad);
target_amp_design = sqrt(max(target_dose_design, 0));
target_pad(center_idx, center_idx) = target_amp_design;
mask_line = false(Nx_pad, Ny_pad);
mask_halo = false(Nx_pad, Ny_pad);
mask_line(center_idx, center_idx) = line_target_mask > 0.5;
mask_halo(center_idx, center_idx) = halo_target_mask > 0.5;
mask_dark = ~(mask_line | mask_halo);

circle_mask_board = (X_grid.^2 + Y_grid.^2) <= (32e-3)^2;
k_board_val = 2 * pi * f0 / c_board;
k_water_val = 2 * pi * f0 / c_water;
k_diff = abs(k_water_val - k_board_val);
phase_step = k_diff * dz;
phase_bias_seed = 0;
if exist('optimal_phase_bias', 'var')
    phase_bias_seed = optimal_phase_bias;
end

[phase_projected_init, ~, phase_bias_seed] = project_phase_to_board( ...
    optimal_initial_phase, phase_step, min_base_layers, circle_mask_board, ...
    phase_bias_seed, true);
[holo_phase, net_num_board, ~] = run_iasa_phase_refinement( ...
    phase_projected_init, phase_bias_seed, phase_step, min_base_layers, circle_mask_board, ...
    target_pad, mask_line, mask_halo, mask_dark, H_forward, H_backward, ...
    Nx, Nx_pad, Ny_pad, iasa_epoch, iasa_anchor_eta, phase_refine_mode);

asm_iasa_amp = compute_asm_focus_field(holo_phase, circle_mask_board, Nx, Ny, H_forward);
asm_iasa_norm = asm_iasa_amp / (max(asm_iasa_amp(:)) + eps);
asm_metrics = calc_image_metrics(asm_iasa_norm, imag_target);
end

function [holo_phase, net_num_board, phase_bias_seed] = run_iasa_phase_refinement( ...
    init_phase, phase_bias_seed, phase_step, min_base_layers, circle_mask_board, ...
    target_pad, mask_line, mask_halo, mask_dark, H_forward, H_backward, ...
    Nx, Nx_pad, Ny_pad, iasa_epoch, iasa_anchor_eta, phase_refine_mode)

center_idx = Nx/2+1:Nx/2+Nx;
board_phase_pad = zeros(Nx_pad, Ny_pad);
board_phase_pad(center_idx, center_idx) = exp(1i * init_phase);
phase_anchor = init_phase;
weight_pad = 0.05 + target_pad * 1.95;

if strcmpi(phase_refine_mode, 'python_only')
    epoch = 0;
else
    epoch = iasa_epoch;
end

[~, net_num_board, phase_bias_seed] = project_phase_to_board( ...
    init_phase, phase_step, min_base_layers, circle_mask_board, phase_bias_seed, true);

for idx = 1:epoch
    U_source = zeros(Nx_pad, Ny_pad);
    center_phase = angle(board_phase_pad(center_idx, center_idx));
    center_source = exp(1i * center_phase);
    center_source(~circle_mask_board) = 0;
    U_source(center_idx, center_idx) = center_source;

    A_source = fftshift(fft2(ifftshift(U_source)));
    U_target = fftshift(ifft2(ifftshift(A_source .* H_forward)));
    rec_amp = abs(U_target);
    peak_val = max(rec_amp(mask_line));
    if peak_val == 0
        peak_val = max(rec_amp(:));
    end
    rec_amp_norm = rec_amp / peak_val;

    if idx > 5
        beta = 0.6;
        correction = (target_pad(mask_line) ./ (rec_amp_norm(mask_line) + 1e-6)) .^ beta;
        weight_pad(mask_line) = min(weight_pad(mask_line) .* correction, 10);
        weight_pad(mask_halo) = 0.05;
        weight_pad(mask_dark) = 0;
    end

    U_target_constrained = weight_pad .* exp(1i * angle(U_target));
    A_target_cons = fftshift(fft2(ifftshift(U_target_constrained)));
    U_source_new = fftshift(ifft2(ifftshift(A_target_cons .* H_backward)));
    source_phase_candidate = angle(U_source_new(center_idx, center_idx));
    [phase_projected_iter_raw, ~, phase_bias_seed] = project_phase_to_board( ...
        source_phase_candidate, phase_step, min_base_layers, circle_mask_board, ...
        phase_bias_seed, true);

    if iasa_anchor_eta < 1
        blended_complex = (1 - iasa_anchor_eta) .* exp(1i * phase_anchor) ...
            + iasa_anchor_eta .* exp(1i * phase_projected_iter_raw);
        blended_phase = angle(blended_complex);
    else
        blended_phase = phase_projected_iter_raw;
    end

    [phase_projected_iter, net_num_board, phase_bias_seed] = project_phase_to_board( ...
        blended_phase, phase_step, min_base_layers, circle_mask_board, ...
        phase_bias_seed, true);
    board_phase_pad = zeros(Nx_pad, Ny_pad);
    board_phase_pad(center_idx, center_idx) = exp(1i * phase_projected_iter);
end

holo_phase = mod(net_num_board * phase_step, 2 * pi);
holo_phase(~circle_mask_board) = 0;
end

function kwave_result = run_board_sonoink_kwave(holo_phase, net_num_board, ...
    circle_mask_board, imag_target, Nx, Ny, Nz, dx, dy, dz, Lz, z_target_dist, ...
    focus_scan_radius, focus_edge_warn_mm, f0, c_water, density_water, ...
    alpha_coeff_water, alpha_power_water, c_board, density_board, ...
    alpha_coeff_board, c_sonoink, density_sonoink, alpha_coeff_sonoink)

fprintf('\nRunning k-Wave: phase board + sonoink medium...\n');
kgrid = kWaveGrid(Nx, dx, Ny, dy, Nz, dz);
medium.sound_speed = c_water * ones(Nx, Ny, Nz, 'single');
medium.density = density_water * ones(Nx, Ny, Nz, 'single');
medium.alpha_coeff = alpha_coeff_water * ones(Nx, Ny, Nz, 'single');
medium.alpha_power = alpha_power_water;

pml_size = 10;
source_z_idx = pml_size + 5;
z_board_start_idx = source_z_idx + 1;
max_layers = max(net_num_board(:));
for layer_idx = 1:max_layers
    layer_mask = net_num_board >= layer_idx;
    z_idx = z_board_start_idx + layer_idx - 1;
    speed_slice = medium.sound_speed(:, :, z_idx);
    density_slice = medium.density(:, :, z_idx);
    alpha_slice = medium.alpha_coeff(:, :, z_idx);
    speed_slice(layer_mask) = c_board;
    density_slice(layer_mask) = density_board;
    alpha_slice(layer_mask) = alpha_coeff_board;
    medium.sound_speed(:, :, z_idx) = speed_slice;
    medium.density(:, :, z_idx) = density_slice;
    medium.alpha_coeff(:, :, z_idx) = alpha_slice;
end

z_board_exit_idx = z_board_start_idx + max_layers - 1;
target_plane_idx = z_board_exit_idx + round(z_target_dist / dz);
if target_plane_idx >= Nz - pml_size
    error('HDSP_sonoink:DomainTooShort', ...
        'Target plane exceeds simulation domain. Increase Nz or reduce z_target_dist.');
end

sonoink_start_idx = z_board_exit_idx + 1;
sonoink_end_idx = Nz - pml_size;
medium.sound_speed(:, :, sonoink_start_idx:sonoink_end_idx) = c_sonoink;
medium.density(:, :, sonoink_start_idx:sonoink_end_idx) = density_sonoink;
medium.alpha_coeff(:, :, sonoink_start_idx:sonoink_end_idx) = alpha_coeff_sonoink;

cfl = 0.3;
t_end = (Lz * 1.5) / c_water;
kgrid.makeTime(medium.sound_speed, cfl, t_end);

source.p_mask = zeros(Nx, Ny, Nz, 'single');
source.p_mask(:, :, source_z_idx) = single(circle_mask_board);
t_vec = kgrid.t_array;
source_sig = sin(2 * pi * f0 * t_vec);
ramp_pts = min(kgrid.Nt, max(1, round(2 / f0 / kgrid.dt)));
window = [linspace(0, 1, ramp_pts), ones(1, kgrid.Nt - ramp_pts)];
source.p = single(source_sig .* window);
source.p_mode = 'dirichlet';

scan_range_idx = round(focus_scan_radius / dz);
z_scan_start = max(1 + pml_size, target_plane_idx - scan_range_idx);
z_scan_end = min(Nz - pml_size, target_plane_idx + scan_range_idx);
sensor.mask = zeros(Nx, Ny, Nz, 'single');
sensor.mask(:, :, z_scan_start:z_scan_end) = 1;
sensor.record = {'p_max'};
sensor.record_start_index = max(1, kgrid.Nt - round(3 / f0 / kgrid.dt));

input_args = {'PMLInside', true, 'PMLSize', pml_size, ...
    'PlotPML', false, 'PlotSim', false, 'DataCast', 'gpuArray-single'};
try
    reset(gpuDevice);
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch
    fprintf('GPU k-Wave path failed, falling back to CPU.\n');
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{1:end-2});
end

p_amp = gather(sensor_data.p_max);
p_field_3d = zeros(Nx, Ny, Nz);
p_field_3d(sensor.mask ~= 0) = p_amp;
scan_vol = p_field_3d(:, :, z_scan_start:z_scan_end);
[best_slice_idx, metrics_z, metrics_corr] = select_best_focus_slice( ...
    scan_vol, imag_target, z_scan_start, z_board_exit_idx, dz);

best_idx_global = z_scan_start + best_slice_idx - 1;
p_focal_amp = p_field_3d(:, :, best_idx_global);
p_focal_norm = p_focal_amp / (max(p_focal_amp(:)) + eps);
actual_z_dist_mm = (best_idx_global - z_board_exit_idx) * dz * 1e3;
design_z_dist_mm = z_target_dist * 1e3;
focus_shift_mm = actual_z_dist_mm - design_z_dist_mm;
focus_edge_margin_idx = min(best_slice_idx - 1, size(scan_vol, 3) - best_slice_idx);
focus_edge_margin_mm = focus_edge_margin_idx * dz * 1e3;

kwave_result = struct();
kwave_result.p_focal_amp = p_focal_amp;
kwave_result.p_focal_norm = p_focal_norm;
kwave_result.metrics_z = metrics_z;
kwave_result.metrics_corr = metrics_corr;
kwave_result.best_corr = max(metrics_corr);
kwave_result.best_idx_global = best_idx_global;
kwave_result.target_plane_idx = target_plane_idx;
kwave_result.z_board_exit_idx = z_board_exit_idx;
kwave_result.actual_z_dist_mm = actual_z_dist_mm;
kwave_result.design_z_dist_mm = design_z_dist_mm;
kwave_result.focus_shift_mm = focus_shift_mm;
kwave_result.focus_edge_margin_mm = focus_edge_margin_mm;
kwave_result.focus_near_edge = focus_edge_margin_mm < focus_edge_warn_mm;
kwave_result.holo_phase = holo_phase;
end

function [best_slice_idx, metrics_z, metrics_corr] = select_best_focus_slice( ...
    scan_vol, target_img, z_scan_start, z_board_exit_idx, dz)
num_slices = size(scan_vol, 3);
target_norm = target_img / (max(target_img(:)) + eps);
target_mean = mean(target_norm(:));
metrics_z = zeros(num_slices, 1);
metrics_corr = zeros(num_slices, 1);
best_corr = -inf;
best_slice_idx = 1;
for idx = 1:num_slices
    amp = scan_vol(:, :, idx);
    amp = (amp - min(amp(:))) / (max(amp(:)) - min(amp(:)) + eps);
    amp_mean = mean(amp(:));
    numerator = sum(sum((target_norm - target_mean) .* (amp - amp_mean)));
    denominator = sqrt(sum(sum((target_norm - target_mean).^2)) ...
        * sum(sum((amp - amp_mean).^2)));
    metrics_corr(idx) = numerator / (denominator + eps);
    metrics_z(idx) = (z_scan_start + idx - 1 - z_board_exit_idx) * dz * 1e3;
    if metrics_corr(idx) > best_corr
        best_corr = metrics_corr(idx);
        best_slice_idx = idx;
    end
end
end

function cure_result = run_sonoink_cure_scan(p_focal_amp, target_mask, ...
    cure_params, pressure_scan, exposure_scan)
roi_amp_median = median(p_focal_amp(target_mask));
if roi_amp_median <= 0 || ~isfinite(roi_amp_median)
    error('HDSP_sonoink:InvalidPressureScale', ...
        'Invalid ROI pressure median. Cannot calibrate cure pressure scan.');
end

scan_records = zeros(numel(pressure_scan) * numel(exposure_scan), 10);
best = struct('IoU', -inf);
record_idx = 0;
for p_idx = 1:numel(pressure_scan)
    target_median_pressure = pressure_scan(p_idx);
    p_scaled = p_focal_amp ./ roi_amp_median .* target_median_pressure;
    for e_idx = 1:numel(exposure_scan)
        exposure_time = exposure_scan(e_idx);
        sim = simulate_cure_from_pressure_map( ...
            p_scaled, exposure_time, cure_params, target_mask);
        metrics = sim.metrics;
        temperature_C = sim.temperature_C;
        Tmax_C = max(temperature_C(:));
        roi_score = mean(sim.cure_score(target_mask));
        peak_score = max(sim.cure_score(:));

        record_idx = record_idx + 1;
        scan_records(record_idx, :) = [target_median_pressure / 1e6, ...
            exposure_time, metrics.IoU, metrics.Dice, ...
            metrics.over_cure_ratio, metrics.under_cure_ratio, ...
            metrics.cured_coverage, Tmax_C, roi_score, peak_score];

        if metrics.IoU > best.IoU
            best.target_median_pressure = target_median_pressure;
            best.exposure_time = exposure_time;
            best.p_scaled = p_scaled;
            best.sim = sim;
            best.metrics = metrics;
            best.IoU = metrics.IoU;
            best.Tmax_C = Tmax_C;
            best.roi_score = roi_score;
            best.peak_score = peak_score;
        end
    end
end

scan_records = scan_records(1:record_idx, :);
top_records = sortrows(scan_records, -3);

cure_result = struct();
cure_result.best = best;
cure_result.scan_records = scan_records;
cure_result.top_records = top_records(1:min(10, size(top_records, 1)), :);
cure_result.pressure_scan = pressure_scan;
cure_result.exposure_scan = exposure_scan;
cure_result.threshold = cure_params.threshold;
cure_result.roi_amp_median_raw = roi_amp_median;
end

function export_overview_figure(fig_path, x, y, target_img, holo_phase, ...
    kwave_result, cure_result, asm_iasa_norm, asm_metrics, kwave_metrics, ...
    asm_kwave_corr)
best = cure_result.best;
target_mask = target_img > 0.5;
error_map = zeros(size(target_mask));
error_map(target_mask & best.sim.cured_mask) = 1;
error_map(target_mask & ~best.sim.cured_mask) = 2;
error_map(~target_mask & best.sim.cured_mask) = 3;

fig = figure('Color', 'w', 'Position', [60, 60, 1700, 980]);
tiledlayout(3, 4, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile; imagesc(x * 1e3, y * 1e3, target_img); axis image;
colormap(gca, gray); colorbar; title('Target'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, holo_phase); axis image;
colormap(gca, hsv); colorbar; clim([0, 2*pi]); title('Board phase'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, asm_iasa_norm); axis image;
colormap(gca, turbo); colorbar;
title(sprintf('ASM Python+IASA\nPCC %.4f | SSIM %.4f', asm_metrics.pcc, asm_metrics.ssim));
xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, kwave_result.p_focal_norm); axis image;
colormap(gca, turbo); colorbar;
title(sprintf('k-Wave sonoink\nPCC %.4f | SSIM %.4f', kwave_metrics.pcc, kwave_metrics.ssim));
xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, best.p_scaled / 1e6); axis image;
colormap(gca, turbo); colorbar;
title(sprintf('Scaled pressure\nROI median %.2f MPa', best.target_median_pressure / 1e6));
xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, best.sim.temperature_C); axis image;
colormap(gca, hot); colorbar;
title(sprintf('Sonoink temperature\nTmax %.1f C', best.Tmax_C));
xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, best.sim.score_components.absorption_gain); axis image;
colormap(gca, turbo); colorbar; title('Self-enhancing gain'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, best.sim.cure_score); axis image;
colormap(gca, turbo); colorbar;
title(sprintf('Gel dose\nThreshold %.2f', cure_result.threshold));
xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, best.sim.cured_mask); axis image;
colormap(gca, [1 1 1; 0.1 0.1 0.3]); colorbar;
title(sprintf('Predicted cure\nIoU %.4f', best.metrics.IoU));
xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, error_map); axis image;
colormap(gca, [0.02 0.02 0.08; 0.1 0.7 0.2; 0.1 0.3 1.0; 1.0 0.25 0.1]);
colorbar; title('Hit / under / over'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile;
plot(kwave_result.metrics_z, kwave_result.metrics_corr, 'b-', 'LineWidth', 1.6); hold on;
plot(kwave_result.actual_z_dist_mm, kwave_result.best_corr, 'ro', 'MarkerSize', 8);
grid on; xlabel('distance from board exit (mm)'); ylabel('PCC');
title(sprintf('Z scan | ASM-kWave %.4f', asm_kwave_corr));

nexttile;
scatter(cure_result.scan_records(:, 1), cure_result.scan_records(:, 2), ...
    22, cure_result.scan_records(:, 3), 'filled');
grid on; colorbar; xlabel('ROI median pressure (MPa)'); ylabel('Exposure (s)');
title('Sonoink cure scan IoU');

exportgraphics(fig, fig_path, 'Resolution', 300);
end

function metrics = calc_image_metrics(pred_img, target_img)
pred_norm = pred_img / (max(pred_img(:)) + eps);
target_norm = target_img / (max(target_img(:)) + eps);
metrics.pcc = corr2(pred_norm, target_norm);
metrics.ssim = ssim(double(pred_norm), double(target_norm));
metrics.nmse = sum((pred_norm(:) - target_norm(:)).^2) / (sum(target_norm(:).^2) + eps);
target_mask = target_norm > 0.5;
metrics.ee = sum(pred_norm(target_mask).^2) / (sum(pred_norm(:).^2) + eps);
end

function print_summary(cure_result, asm_metrics, kwave_metrics, kwave_result, ...
    asm_kwave_corr, asm_kwave_nmse, out_dir, cure_params)
best = cure_result.best;
fprintf('\n==================================================\n');
fprintf('Sonoink full-flow validation summary\n');
fprintf('Cure system: %s | material: %s\n', cure_params.model_name, cure_params.material);
fprintf('Design/best distance: %.2f / %.2f mm (shift %.2f mm)\n', ...
    kwave_result.design_z_dist_mm, kwave_result.actual_z_dist_mm, ...
    kwave_result.focus_shift_mm);
fprintf('Focus edge margin: %.2f mm\n', kwave_result.focus_edge_margin_mm);
if kwave_result.focus_near_edge
    fprintf('Warning: best focus plane is close to scan boundary.\n');
end
fprintf('ASM PCC/SSIM/NMSE/EE: %.4f / %.4f / %.4f / %.2f%%\n', ...
    asm_metrics.pcc, asm_metrics.ssim, asm_metrics.nmse, asm_metrics.ee * 100);
fprintf('k-Wave PCC/SSIM/NMSE/EE: %.4f / %.4f / %.4f / %.2f%%\n', ...
    kwave_metrics.pcc, kwave_metrics.ssim, kwave_metrics.nmse, kwave_metrics.ee * 100);
fprintf('ASM(IASA)-kWave PCC/NMSE: %.4f / %.4f\n', ...
    asm_kwave_corr, asm_kwave_nmse);
fprintf('--------------------------------------------------\n');
fprintf('Best sonoink cure point: %.2f MPa + %.2f s\n', ...
    best.target_median_pressure / 1e6, best.exposure_time);
fprintf('Threshold: %.2f fixed gel-dose criterion\n', cure_result.threshold);
fprintf('Tmax: %.1f C | ROI score mean: %.4f | peak score: %.4f\n', ...
    best.Tmax_C, best.roi_score, best.peak_score);
fprintf('Coverage/Over/Under: %.1f%% / %.1f%% / %.1f%%\n', ...
    best.metrics.cured_coverage * 100, ...
    best.metrics.over_cure_ratio * 100, ...
    best.metrics.under_cure_ratio * 100);
fprintf('IoU/Dice: %.4f / %.4f\n', best.metrics.IoU, best.metrics.Dice);
fprintf('Top-5 scan records: P MPa | Exp s | IoU | Dice | Over | Under | Coverage | Tmax C | ROI score\n');
for idx = 1:min(5, size(cure_result.top_records, 1))
    row = cure_result.top_records(idx, :);
    fprintf('  #%02d %.2f | %.2f | %.4f | %.4f | %.1f%% | %.1f%% | %.1f%% | %.1f | %.4f\n', ...
        idx, row(1), row(2), row(3), row(4), row(5) * 100, ...
        row(6) * 100, row(7) * 100, row(8), row(9));
end
fprintf('Figures and data saved to: %s\n', out_dir);
fprintf('==================================================\n');
end
