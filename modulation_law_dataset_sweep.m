clear; close all; clc;
try
    reset(gpuDevice);
catch
end

addpath(pwd);
addpath('F:\MATLAB\code\HDSP\HDSP\HDSP0420');
rng(9426);

cfg = default_modulation_sweep_config();
case_table = build_modulation_case_table(cfg);
if cfg.max_cases > 0
    case_table = case_table(1:min(cfg.max_cases, height(case_table)), :);
end
ensure_dir(cfg.output_dir);

fprintf('==================================================\n');
fprintf('HDSP modulation-law dataset sweep\n');
fprintf('Study mode: %s | cases: %d | output: %s\n', cfg.study_mode, height(case_table), cfg.output_dir);
fprintf('Grid: %d x %d | dx %.4f mm | exit-only z after board %.2f mm\n', ...
    cfg.Nx, cfg.Nx, cfg.dx * 1e3, cfg.exit_probe_after_board_m * 1e3);
fprintf('==================================================\n');

[base, asm_grid] = prepare_base_modulation_design(cfg);
summary_rows = repmat(empty_summary_row(), 0, 1);

for case_idx = 1:height(case_table)
    case_params = table2struct(case_table(case_idx, :));
    case_label = sprintf('case_%03d_%s', case_idx, sanitize_label(case_params.case_name));
    case_dir = fullfile(cfg.output_dir, case_label);
    ensure_dir(case_dir);
    metrics_path = fullfile(case_dir, 'case_metrics.mat');

    if cfg.resume && exist(metrics_path, 'file')
        loaded = load(metrics_path, 'metrics');
        metrics = loaded.metrics;
        if cfg.export_field_validation && ~exist(modulation_field_validation_path(case_dir, metrics.case_label), 'file')
            loaded_field = load(metrics_path, 'board', 'sim');
            export_modulation_field_validation_case(case_dir, metrics, loaded_field.board, loaded_field.sim, base, cfg);
        end
        fprintf('[%03d/%03d] skip existing %s | mode %s | PCC %.4f\n', ...
            case_idx, height(case_table), case_label, cfg.study_mode, metrics.target_pcc);
    else
        fprintf('[%03d/%03d] running %s\n', case_idx, height(case_table), case_label);
        board = build_modulation_board_case(base, asm_grid, cfg, case_params);
        sim = run_modulation_kwave_case(board, base, cfg);
        metrics = analyze_modulation_case(board, sim, base, cfg, case_params, case_label);
        save(metrics_path, 'metrics', 'board', 'sim', 'case_params', '-v7.3');
        write_json_file(fullfile(case_dir, 'case_metrics.json'), metrics);

        if cfg.export_exit_surrogate && isfield(sim, 'exit_amp_norm') && any(isfinite(sim.exit_amp_norm(:)))
            export_modulation_surrogate_case(case_dir, metrics, board, sim, base, cfg);
        end
        if cfg.export_field_validation && isfield(sim, 'exit_complex') && any(isfinite(abs(sim.exit_complex(:))))
            export_modulation_field_validation_case(case_dir, metrics, board, sim, base, cfg);
        end
    end

    summary_rows(end + 1) = metrics_to_summary_row(metrics); %#ok<SAGROW>
    writetable(struct2table(summary_rows), fullfile(cfg.output_dir, 'modulation_dataset_summary.csv'));
end

summary_table = struct2table(summary_rows);
save(fullfile(cfg.output_dir, 'modulation_dataset_summary.mat'), 'summary_table', 'cfg', 'case_table');
fprintf('\nDataset sweep complete. Summary: %s\n', fullfile(cfg.output_dir, 'modulation_dataset_summary.csv'));

try
    reset(gpuDevice);
catch
end

function cfg = default_modulation_sweep_config()
cfg = struct();
cfg.study_mode = getenv_default('HDSP_MODULATION_STUDY_MODE', 'exit_only'); % exit_only | target_field | both
cfg.Nx = str2double(getenv_default('HDSP_MODULATION_NX', '512'));
cfg.Lx = 65e-3;
cfg.Ny = cfg.Nx;
cfg.Ly = cfg.Lx;
cfg.z_target_dist = 16e-3;
cfg.focus_scan_radius = 6e-3;
cfg.exit_probe_after_board_m = 4e-3;
cfg.f0 = 4.5e6;
cfg.c_water = 1480;
cfg.c_board = 2430;
cfg.density_water = 997;
cfg.density_board = 1100;
cfg.alpha_coeff_water = 0.002;
cfg.alpha_power_water = 1.5;
cfg.alpha_coeff_board = 1.5;
cfg.lambda_water = cfg.c_water / cfg.f0;
cfg.phase_refine_mode = getenv_default('HDSP_MODULATION_PHASE_REFINE', 'python_iasa');
cfg.iasa_epoch = str2double(getenv_default('HDSP_MODULATION_IASA_EPOCH', '150'));
cfg.iasa_anchor_eta = 1.0;
cfg.min_base_layers_default = 2;
cfg.aperture_radius = 32e-3;
cfg.pad_factor = 2;
cfg.pml_size = 10;
cfg.cfl = 0.3;
cfg.transport_dir = getenv_default('HDSP_TRANSPORT_DIR', 'C:\Users\Zh89\Desktop\transport');
cfg.output_dir = getenv_default('HDSP_MODULATION_OUTPUT_DIR', fullfile(pwd, 'modulation_law_dataset'));
cfg.resume = strcmpi(getenv_default('HDSP_MODULATION_RESUME', '1'), '1');
cfg.max_cases = str2double(getenv_default('HDSP_MODULATION_MAX_CASES', '0'));
cfg.export_exit_surrogate = strcmpi(getenv_default('HDSP_MODULATION_EXPORT_SURROGATE', '1'), '1');
cfg.export_field_validation = strcmpi(getenv_default('HDSP_MODULATION_EXPORT_FIELD_VALIDATION', '1'), '1');
cfg.patch_size = 9;
cfg.sample_stride = str2double(getenv_default('HDSP_MODULATION_SAMPLE_STRIDE', '2'));
cfg.max_samples_per_run = str2double(getenv_default('HDSP_MODULATION_MAX_SAMPLES', '30000'));
cfg.dx = cfg.Lx / cfg.Nx;
cfg.dy = cfg.dx;
cfg.dz = cfg.dx;
end

function case_table = build_modulation_case_table(cfg)
phase_sign = ["same", "opposite"];
phase_bias_delta = [-pi/4, 0, pi/4];
layer_offset = [-1, 0, 1];
min_base_layers = [cfg.min_base_layers_default];
quantize_mode = ["dither", "round"];

rows = {};
for ps = phase_sign
    for bd = phase_bias_delta
        for lo = layer_offset
            for mb = min_base_layers
                for qm = quantize_mode
                    rows(end + 1, :) = { ...
                        sprintf('%s_bias%+.2f_layer%+d_%s', char(ps), bd, lo, char(qm)), ...
                        char(ps), bd, lo, mb, char(qm)}; %#ok<AGROW>
                end
            end
        end
    end
end
case_table = cell2table(rows, 'VariableNames', ...
    {'case_name', 'phase_sign', 'phase_bias_delta', 'layer_offset', 'min_base_layers', 'quantize_mode'});
end

function [base, asm_grid] = prepare_base_modulation_design(cfg)
Nx = cfg.Nx;
dx = cfg.dx;
x = (-Nx/2 : Nx/2-1) * dx;
[Y_grid, X_grid] = meshgrid(x, x);

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

ensure_dir(cfg.transport_dir);
export_path = fullfile(cfg.transport_dir, 'target_for_python.mat');
python_payload = struct( ...
    'imag_target', imag_target, ...
    'imag_target_design', imag_target_design, ...
    'Nx', Nx, ...
    'Lx', cfg.Lx, ...
    'lambda_water', cfg.lambda_water, ...
    'z_target_dist', cfg.z_target_dist, ...
    'dx', dx, ...
    'dz', cfg.dz, ...
    'f0', cfg.f0, ...
    'c_water', cfg.c_water, ...
    'c_board', cfg.c_board, ...
    'density_water', cfg.density_water, ...
    'density_board', cfg.density_board, ...
    'alpha_coeff_water', cfg.alpha_coeff_water, ...
    'thermal_sigma_px', thermal_sigma_px, ...
    'min_base_layers', cfg.min_base_layers_default);
save(export_path, '-struct', 'python_payload');

import_path = fullfile(cfg.transport_dir, 'dl_phase_init.mat');
if ~exist(import_path, 'file')
    error('modulation_law_dataset_sweep:MissingInitialPhase', ...
        'Missing %s. Target was exported to %s; run the Python initial-phase step first.', import_path, export_path);
end
loaded = load(import_path, 'optimal_initial_phase', 'optimal_phase_bias', ...
    'target_dose_design', 'line_target_mask', 'halo_target_mask');
if ~isequal(size(loaded.optimal_initial_phase), [Nx, Nx])
    error('modulation_law_dataset_sweep:GridMismatch', ...
        'dl_phase_init.mat grid does not match Nx=%d. Regenerate Python initial phase.', Nx);
end

Nx_pad = Nx * cfg.pad_factor;
Lx_pad = cfg.Lx * cfg.pad_factor;
dk_pad = 2 * pi / Lx_pad;
kx_pad = (-Nx_pad/2 : Nx_pad/2-1) * dk_pad;
[Kx_pad, Ky_pad] = meshgrid(kx_pad, kx_pad);
k_water_wave = 2 * pi / cfg.lambda_water;
Kz_sq = k_water_wave^2 - Kx_pad.^2 - Ky_pad.^2;
propagating = (Kz_sq > 0);
Kz = zeros(size(Kz_sq));
Kz(propagating) = sqrt(Kz_sq(propagating));
H_forward = zeros(size(Kz_sq));
H_forward(propagating) = exp(1i * Kz(propagating) * cfg.z_target_dist);
H_backward = conj(H_forward);
center_idx = Nx/2+1:Nx/2+Nx;

target_pad = zeros(Nx_pad, Nx_pad);
target_amp_design = sqrt(max(loaded.target_dose_design, 0));
target_pad(center_idx, center_idx) = target_amp_design;
mask_line = false(Nx_pad, Nx_pad);
mask_halo = false(Nx_pad, Nx_pad);
mask_line(center_idx, center_idx) = loaded.line_target_mask > 0.5;
mask_halo(center_idx, center_idx) = loaded.halo_target_mask > 0.5;
mask_dark = ~(mask_line | mask_halo);

circle_mask_board = (X_grid.^2 + Y_grid.^2) <= cfg.aperture_radius^2;
phase_step = abs(2 * pi * cfg.f0 / cfg.c_water - 2 * pi * cfg.f0 / cfg.c_board) * cfg.dz;
phase_bias_seed = 0;
if isfield(loaded, 'optimal_phase_bias')
    phase_bias_seed = loaded.optimal_phase_bias;
end
[phase_projected_init, ~, phase_bias_seed] = project_phase_to_board( ...
    loaded.optimal_initial_phase, phase_step, cfg.min_base_layers_default, circle_mask_board, phase_bias_seed, true);
[holo_phase, net_num_board, phase_bias_python_iasa] = run_iasa_phase_refinement_local( ...
    phase_projected_init, phase_bias_seed, phase_step, cfg.min_base_layers_default, circle_mask_board, ...
    target_pad, mask_line, mask_halo, mask_dark, H_forward, H_backward, ...
    Nx, Nx_pad, center_idx, cfg.iasa_epoch, cfg.iasa_anchor_eta, cfg.phase_refine_mode);

base = struct();
base.x = x;
base.y = x;
base.X_grid = X_grid;
base.Y_grid = Y_grid;
base.imag_target = imag_target;
base.target_norm = imag_target / (max(imag_target(:)) + eps);
base.target_mask = base.target_norm > 0.5;
base.circle_mask_board = circle_mask_board;
base.holo_phase = holo_phase;
base.net_num_board_base = net_num_board;
base.phase_bias_python_iasa = phase_bias_python_iasa;
base.phase_step = phase_step;
base.phase_bias_seed = phase_bias_seed;
base.center_idx = center_idx;

asm_grid = struct();
asm_grid.Nx_pad = Nx_pad;
asm_grid.H_forward = H_forward;
asm_grid.H_backward = H_backward;
asm_grid.Kz = Kz;
asm_grid.propagating = propagating;
end

function board = build_modulation_board_case(base, asm_grid, cfg, case_params)
phase_in = base.holo_phase;
if strcmpi(case_params.phase_sign, 'opposite')
    phase_in = -phase_in;
end
phase_in = phase_in + case_params.phase_bias_delta;
[~, net_num_board, best_offset] = project_phase_for_quantize_mode( ...
    phase_in, base.phase_step, case_params.min_base_layers, base.circle_mask_board, ...
    base.phase_bias_seed + case_params.phase_bias_delta, case_params.quantize_mode);
net_num_board = net_num_board + case_params.layer_offset;
net_num_board = max(net_num_board, case_params.min_base_layers);
net_num_board(~base.circle_mask_board) = case_params.min_base_layers;
phase_projected = mod(net_num_board * base.phase_step, 2 * pi);
phase_projected(~base.circle_mask_board) = 0;

thickness_map = net_num_board * cfg.dz;
[grad_x, grad_y] = gradient(thickness_map, cfg.dx, cfg.dy);
thickness_grad_norm = hypot(grad_x, grad_y);
local_thickness_mean = imgaussfilt(thickness_map, 1.0);
local_thickness_std = sqrt(max(imgaussfilt(thickness_map.^2, 1.0) - local_thickness_mean.^2, 0));
aperture_edge_distance_mm = bwdist(~base.circle_mask_board) * cfg.dx * 1e3;
asm_amp = compute_asm_focus_field(phase_projected, base.circle_mask_board, cfg.Nx, cfg.Ny, asm_grid.H_forward);
asm_norm = asm_amp / (max(asm_amp(:)) + eps);

board = struct();
board.phase = phase_projected;
board.net_num_board = net_num_board;
board.thickness_map = thickness_map;
board.thickness_grad_norm = thickness_grad_norm;
board.local_thickness_mean = local_thickness_mean;
board.local_thickness_std = local_thickness_std;
board.aperture_edge_distance_mm = aperture_edge_distance_mm;
board.asm_norm = asm_norm;
board.asm_metrics = calc_image_metrics_local(asm_norm, base.target_norm);
board.best_offset = best_offset;
end

function sim = run_modulation_kwave_case(board, base, cfg)
mode = lower(string(cfg.study_mode));
run_target = any(mode == ["target_field", "both"]);

pml_size = cfg.pml_size;
source_z_idx = pml_size + 5;
z_board_start_idx = source_z_idx + 1;
max_layers = max(board.net_num_board(:));
z_board_exit_idx = z_board_start_idx + max_layers;
z_exit_probe_idx = z_board_exit_idx + max(1, round(cfg.exit_probe_after_board_m / cfg.dz));
target_plane_idx = z_board_exit_idx + round(cfg.z_target_dist / cfg.dz);
scan_range_idx = round(cfg.focus_scan_radius / cfg.dz);

if run_target
    z_scan_start = max(target_plane_idx - scan_range_idx, pml_size + 2);
    z_scan_end = target_plane_idx + scan_range_idx;
    Nz_required = z_scan_end + pml_size + 12;
else
    z_scan_start = z_exit_probe_idx;
    z_scan_end = z_exit_probe_idx;
    Nz_required = z_exit_probe_idx + pml_size + 12;
end
Nz = next_fast_grid_size(Nz_required);
fprintf('  k-Wave grid Nz required=%d -> using %d | source points=%d | scan planes=%d\n', ...
    Nz_required, Nz, nnz(base.circle_mask_board), z_scan_end - z_scan_start + 1);

kgrid = kWaveGrid(cfg.Nx, cfg.dx, cfg.Ny, cfg.dy, Nz, cfg.dz);
medium.sound_speed = cfg.c_water * ones(cfg.Nx, cfg.Ny, Nz, 'single');
medium.density = cfg.density_water * ones(cfg.Nx, cfg.Ny, Nz, 'single');
medium.alpha_coeff = cfg.alpha_coeff_water * ones(cfg.Nx, cfg.Ny, Nz, 'single');
medium.alpha_power = cfg.alpha_power_water;
for row = 1:cfg.Nx
    for col = 1:cfg.Ny
        n_layers = board.net_num_board(row, col);
        if n_layers > 0
            z_end = z_board_start_idx + n_layers - 1;
            medium.sound_speed(row, col, z_board_start_idx:z_end) = cfg.c_board;
            medium.density(row, col, z_board_start_idx:z_end) = cfg.density_board;
            medium.alpha_coeff(row, col, z_board_start_idx:z_end) = cfg.alpha_coeff_board;
        end
    end
end

t_end = (Nz * cfg.dz * 1.8) / cfg.c_water;
kgrid.makeTime(medium.sound_speed, cfg.cfl, t_end);
source.p_mask = zeros(cfg.Nx, cfg.Ny, Nz, 'single');
source.p_mask(:, :, source_z_idx) = single(base.circle_mask_board);
t_vec = reshape(kgrid.t_array, 1, []);
source_sig = sin(2 * pi * cfg.f0 .* t_vec);
ramp_pts = min(kgrid.Nt, max(1, round(2 / cfg.f0 / kgrid.dt)));
source.p = single(source_sig .* [linspace(0, 1, ramp_pts), ones(1, kgrid.Nt - ramp_pts)]);
source.p_mode = 'dirichlet';

sensor.mask = zeros(cfg.Nx, cfg.Ny, Nz, 'single');
sensor.mask(:, :, z_exit_probe_idx) = 1;
if run_target
    sensor.mask(:, :, z_scan_start:z_scan_end) = 1;
end
sensor.record = {'p', 'p_max'};
sensor.record_start_index = max(1, kgrid.Nt - round(3 / cfg.f0 / kgrid.dt));
input_args = {'PMLInside', true, 'PMLSize', pml_size, 'PlotPML', false, 'PlotSim', false, 'DataCast', 'gpuArray-single'};
try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch
    fprintf('GPU path failed, falling back to CPU.\n');
    medium_cpu = cast_medium_for_cpu(medium);
    source_cpu = cast_source_for_cpu(source);
    sensor_cpu = cast_sensor_for_cpu(sensor);
    sensor_data = kspaceFirstOrder3D(kgrid, medium_cpu, source_cpu, sensor_cpu, input_args{1:end-2});
end

p_amp = gather(sensor_data.p_max);
p_field_3d = zeros(cfg.Nx, cfg.Ny, Nz);
p_field_3d(sensor.mask ~= 0) = p_amp;
exit_amp = p_field_3d(:, :, z_exit_probe_idx);
exit_amp_norm = exit_amp / (max(exit_amp(:)) + eps);
p_time = gather(sensor_data.p);
t_record = kgrid.t_array(sensor.record_start_index:end);
p_complex_vec = demodulate_kwave_pressure(p_time, t_record, cfg.f0);
p_complex_3d = complex(zeros(cfg.Nx, cfg.Ny, Nz));
p_complex_3d(sensor.mask ~= 0) = p_complex_vec;
exit_complex = p_complex_3d(:, :, z_exit_probe_idx);
ideal_complex = exp(1i * board.phase) .* base.circle_mask_board;
ratio_same = zeros(cfg.Nx, cfg.Ny);
ratio_opposite = zeros(cfg.Nx, cfg.Ny);
ratio_same(base.circle_mask_board) = exit_complex(base.circle_mask_board) ./ ...
    (ideal_complex(base.circle_mask_board) + eps);
ratio_opposite(base.circle_mask_board) = conj(exit_complex(base.circle_mask_board)) ./ ...
    (ideal_complex(base.circle_mask_board) + eps);

sim = struct();
sim.study_mode = cfg.study_mode;
sim.z_board_exit_idx = z_board_exit_idx;
sim.z_exit_probe_idx = z_exit_probe_idx;
sim.exit_amp = exit_amp;
sim.exit_amp_norm = exit_amp_norm;
sim.exit_complex = exit_complex;
sim.ideal_complex = ideal_complex;
sim.complex_ratio_same = ratio_same;
sim.complex_ratio_opposite = ratio_opposite;
sim.target_amp = NaN(cfg.Nx, cfg.Ny);
sim.target_amp_norm = NaN(cfg.Nx, cfg.Ny);
sim.best_z_mm = NaN;
sim.focus_search_edge_margin_mm = NaN;
sim.focus_search_near_edge = false;

if run_target
    scan_vol = p_field_3d(:, :, z_scan_start:z_scan_end);
    best_corr = -inf;
    best_slice_idx = 1;
    target_norm = base.target_norm;
    metrics_corr = zeros(size(scan_vol, 3), 1);
    metrics_z = zeros(size(scan_vol, 3), 1);
    for idx = 1:size(scan_vol, 3)
        slice_norm = scan_vol(:, :, idx);
        slice_norm = (slice_norm - min(slice_norm(:))) ./ (max(slice_norm(:)) - min(slice_norm(:)) + eps);
        current_corr = corr2(slice_norm, target_norm);
        metrics_corr(idx) = current_corr;
        metrics_z(idx) = (z_scan_start + idx - 1 - z_board_exit_idx) * cfg.dz * 1e3;
        if current_corr > best_corr
            best_corr = current_corr;
            best_slice_idx = idx;
        end
    end
    best_idx_global = z_scan_start + best_slice_idx - 1;
    sim.scan_metrics_z_mm = metrics_z;
    sim.scan_metrics_corr = metrics_corr;
    sim.target_amp = scan_vol(:, :, best_slice_idx);
    sim.target_amp_norm = sim.target_amp / (max(sim.target_amp(:)) + eps);
    sim.best_z_mm = (best_idx_global - z_board_exit_idx) * cfg.dz * 1e3;
    sim.focus_search_edge_margin_mm = min(best_slice_idx - 1, size(scan_vol, 3) - best_slice_idx) * cfg.dz * 1e3;
    sim.focus_search_near_edge = sim.focus_search_edge_margin_mm < 0.5;
end
end

function metrics = analyze_modulation_case(board, sim, base, cfg, case_params, case_label)
exit_vals = sim.exit_amp_norm(base.circle_mask_board);
target_metrics = empty_image_metrics_local();
asm_kwave_pcc = NaN;
if any(isfinite(sim.target_amp_norm(:)))
    target_metrics = calc_image_metrics_local(sim.target_amp_norm, base.target_norm);
    asm_kwave_pcc = corr2(board.asm_norm, sim.target_amp_norm);
end

layer_vals = board.net_num_board(base.circle_mask_board);
thick_vals = board.thickness_map(base.circle_mask_board);
grad_vals = board.thickness_grad_norm(base.circle_mask_board);
local_std_vals = board.local_thickness_std(base.circle_mask_board);
edge_vals = board.aperture_edge_distance_mm(base.circle_mask_board);

metrics = struct();
metrics.case_label = case_label;
metrics.study_mode = cfg.study_mode;
metrics.phase_sign = case_params.phase_sign;
metrics.phase_bias_delta = case_params.phase_bias_delta;
metrics.layer_offset = case_params.layer_offset;
metrics.min_base_layers = case_params.min_base_layers;
metrics.quantize_mode = case_params.quantize_mode;
metrics.asm_pcc = board.asm_metrics.pcc;
metrics.asm_ssim = board.asm_metrics.ssim;
metrics.asm_nmse = board.asm_metrics.nmse;
metrics.target_pcc = target_metrics.pcc;
metrics.target_ssim = target_metrics.ssim;
metrics.target_nmse = target_metrics.nmse;
metrics.target_ee = target_metrics.ee;
metrics.asm_kwave_pcc = asm_kwave_pcc;
metrics.best_z_mm = sim.best_z_mm;
metrics.focus_search_edge_margin_mm = sim.focus_search_edge_margin_mm;
metrics.focus_search_near_edge = sim.focus_search_near_edge;
metrics.exit_amp_cv = std(exit_vals(:)) / (mean(exit_vals(:)) + eps);
metrics.exit_amp_min_ratio = min(exit_vals(:)) / (max(exit_vals(:)) + eps);
ratio_vals = sim.complex_ratio_opposite(base.circle_mask_board);
metrics.exit_ratio_amp_cv = std(abs(ratio_vals(:))) / (mean(abs(ratio_vals(:))) + eps);
metrics.exit_ratio_phase_std_rad = std(angle(ratio_vals(:)));
metrics.layer_min = min(layer_vals(:));
metrics.layer_max = max(layer_vals(:));
metrics.layer_mean = mean(layer_vals(:));
metrics.thickness_mean_mm = mean(thick_vals(:)) * 1e3;
metrics.thickness_std_mm = std(thick_vals(:)) * 1e3;
metrics.thickness_grad_mean = mean(grad_vals(:));
metrics.local_std_amp_corr = corr2_safe(local_std_vals, exit_vals);
metrics.edge_dist_amp_corr = corr2_safe(edge_vals, exit_vals);
metrics.multi_factor_r2 = fit_exit_amp_linear_r2(thick_vals, grad_vals, local_std_vals, edge_vals, exit_vals);
metrics.Nx = cfg.Nx;
metrics.dx_mm = cfg.dx * 1e3;
metrics.z_exit_probe_offset_mm = cfg.exit_probe_after_board_m * 1e3;
metrics.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
fprintf('  ASM PCC %.4f | target PCC %.4f | exit CV %.4f | R2 %.4f\n', ...
    metrics.asm_pcc, metrics.target_pcc, metrics.exit_amp_cv, metrics.multi_factor_r2);
end

function export_modulation_surrogate_case(case_dir, metrics, board, sim, base, cfg)
run_meta = struct( ...
    'run_label', metrics.case_label, ...
    'patch_size', cfg.patch_size, ...
    'sample_stride', cfg.sample_stride, ...
    'max_samples_per_run', cfg.max_samples_per_run, ...
    'Nx', cfg.Nx, 'Ny', cfg.Ny, 'dx', cfg.dx, 'dz', cfg.dz, ...
    'f0', cfg.f0, 'Lx', cfg.Lx, 'z_target_dist', cfg.z_target_dist, ...
    'c_water', cfg.c_water, 'density_water', cfg.density_water, 'alpha_coeff_water', cfg.alpha_coeff_water, ...
    'c_board', cfg.c_board, 'density_board', cfg.density_board, 'alpha_coeff_board', cfg.alpha_coeff_board, ...
    'c_pdms', NaN, 'density_pdms', NaN, 'alpha_coeff_pdms', NaN, ...
    'pdms_thickness_mm', NaN, 'actual_z_dist_mm', sim.best_z_mm);
run_metrics = struct( ...
    'exit_amp_cv', metrics.exit_amp_cv, ...
    'local_std_amp_corr', metrics.local_std_amp_corr, ...
    'edge_dist_amp_corr', metrics.edge_dist_amp_corr, ...
    'multi_factor_r2', metrics.multi_factor_r2, ...
    'board_exit_asm_pcc', metrics.asm_pcc, ...
    'board_exit_kwave_corr', metrics.asm_kwave_pcc);
export_exit_amp_surrogate_run( ...
    case_dir, run_meta, run_metrics, ...
    board.thickness_map, board.thickness_grad_norm, sim.exit_amp_norm, ...
    base.circle_mask_board, base.x, base.y, cfg.dx, board.net_num_board, ...
    board.aperture_edge_distance_mm, board.local_thickness_mean, board.local_thickness_std, ...
    sim.complex_ratio_same, sim.complex_ratio_opposite);
end

function export_modulation_field_validation_case(case_dir, metrics, board, sim, base, cfg)
field_file = modulation_field_validation_path(case_dir, metrics.case_label);
run_meta = struct( ...
    'run_label', metrics.case_label, ...
    'patch_size', cfg.patch_size, ...
    'Nx', cfg.Nx, 'Ny', cfg.Ny, 'dx', cfg.dx, 'dy', cfg.dy, 'dz', cfg.dz, ...
    'f0', cfg.f0, 'Lx', cfg.Lx, 'z_target_dist', cfg.z_target_dist, ...
    'z_exit_probe_offset_mm', cfg.exit_probe_after_board_m * 1e3, ...
    'c_water', cfg.c_water, 'density_water', cfg.density_water, 'alpha_coeff_water', cfg.alpha_coeff_water, ...
    'c_board', cfg.c_board, 'density_board', cfg.density_board, 'alpha_coeff_board', cfg.alpha_coeff_board);
valid_mask = logical(base.circle_mask_board);
x_mm = single(base.x(:)' * 1e3);
y_mm = single(base.y(:)' * 1e3);
thickness_map = single(board.thickness_map);
thickness_grad_norm = single(board.thickness_grad_norm);
local_thickness_mean = single(board.local_thickness_mean);
local_thickness_std = single(board.local_thickness_std);
aperture_edge_distance_mm = single(board.aperture_edge_distance_mm);
net_num_board = single(board.net_num_board);
board_phase = single(board.phase);
exit_amp_norm = single(sim.exit_amp_norm);
ideal_complex_real = single(real(sim.ideal_complex));
ideal_complex_imag = single(imag(sim.ideal_complex));
exit_complex_real = single(real(sim.exit_complex));
exit_complex_imag = single(imag(sim.exit_complex));
ratio_same_real = single(real(sim.complex_ratio_same));
ratio_same_imag = single(imag(sim.complex_ratio_same));
ratio_opposite_real = single(real(sim.complex_ratio_opposite));
ratio_opposite_imag = single(imag(sim.complex_ratio_opposite));
save(field_file, 'run_meta', 'valid_mask', 'x_mm', 'y_mm', ...
    'thickness_map', 'thickness_grad_norm', 'local_thickness_mean', 'local_thickness_std', ...
    'aperture_edge_distance_mm', 'net_num_board', 'board_phase', 'exit_amp_norm', ...
    'ideal_complex_real', 'ideal_complex_imag', 'exit_complex_real', 'exit_complex_imag', ...
    'ratio_same_real', 'ratio_same_imag', 'ratio_opposite_real', 'ratio_opposite_imag');
fprintf('Field validation package exported: %s\n', field_file);
end

function field_file = modulation_field_validation_path(case_dir, case_label)
field_file = fullfile(case_dir, sprintf('%s_field_validation.mat', case_label));
end

function [holo_phase, net_num_board, phase_bias_seed] = run_iasa_phase_refinement_local( ...
    init_phase, phase_bias_seed, phase_step, min_base_layers, circle_mask_board, ...
    target_pad, mask_line, mask_halo, mask_dark, H_forward, H_backward, ...
    ~, Nx_pad, center_idx, epoch, iasa_anchor_eta, phase_refine_mode)

if strcmpi(phase_refine_mode, 'python_only')
    epoch = 0;
end
phase_anchor = init_phase;
[~, net_num_board, phase_bias_seed] = project_phase_to_board( ...
    init_phase, phase_step, min_base_layers, circle_mask_board, phase_bias_seed, true);
board_phase_pad = zeros(Nx_pad, Nx_pad);
board_phase_pad(center_idx, center_idx) = exp(1i * mod(net_num_board * phase_step, 2 * pi));
weight_pad = 0.05 + target_pad * 1.95;

for idx = 1:epoch
    U_source = board_phase_pad;
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
        source_phase_candidate, phase_step, min_base_layers, circle_mask_board, phase_bias_seed, true);
    if iasa_anchor_eta < 1
        blended_complex = (1 - iasa_anchor_eta) .* exp(1i * phase_anchor) + ...
            iasa_anchor_eta .* exp(1i * phase_projected_iter_raw);
        blended_phase = angle(blended_complex);
    else
        blended_phase = phase_projected_iter_raw;
    end
    [phase_projected_iter, net_num_board, phase_bias_seed] = project_phase_to_board( ...
        blended_phase, phase_step, min_base_layers, circle_mask_board, phase_bias_seed, true);
    board_phase_pad(center_idx, center_idx) = exp(1i * phase_projected_iter);
end
holo_phase = mod(net_num_board * phase_step, 2 * pi);
holo_phase(~circle_mask_board) = 0;
end

function [phase_projected, layer_map, best_offset] = project_phase_for_quantize_mode( ...
    phase_in, phase_step, base_layers, mask, offset_seed, quantize_mode)
if strcmpi(quantize_mode, 'dither')
    [phase_projected, layer_map, best_offset] = project_phase_to_board( ...
        phase_in, phase_step, base_layers, mask, offset_seed, true);
    return;
end

phase_wrapped = mod(phase_in, 2*pi);
offset_candidates = offset_seed + linspace(-0.5, 0.5, 9) * phase_step;
best_cost = inf;
best_offset = offset_seed;
layer_map = base_layers * ones(size(phase_in));
phase_projected = zeros(size(phase_in));
max_layer_index = base_layers + ceil((2*pi) / phase_step) + 1;
for idx = 1:numel(offset_candidates)
    offset_now = offset_candidates(idx);
    layer_cont = mod(phase_wrapped + offset_now, 2*pi) / phase_step + base_layers;
    switch lower(quantize_mode)
        case 'floor'
            candidate_layers = floor(layer_cont);
        case 'ceil'
            candidate_layers = ceil(layer_cont);
        otherwise
            candidate_layers = round(layer_cont);
    end
    candidate_layers = min(max(candidate_layers, base_layers), max_layer_index);
    phase_candidate = mod(candidate_layers * phase_step, 2*pi);
    residual = angle(exp(1i * (phase_candidate - mod(phase_wrapped + offset_now, 2*pi))));
    cost = mean(residual(mask).^2);
    if cost < best_cost
        best_cost = cost;
        best_offset = offset_now;
        layer_map = candidate_layers;
        phase_projected = phase_candidate;
    end
end
layer_map(~mask) = base_layers;
phase_projected(~mask) = 0;
best_offset = mod(best_offset, 2*pi);
end

function row = empty_summary_row()
row = struct('case_label', "", 'study_mode', "", 'phase_sign', "", 'phase_bias_delta', NaN, ...
    'layer_offset', NaN, 'min_base_layers', NaN, 'quantize_mode', "", ...
    'asm_pcc', NaN, 'target_pcc', NaN, 'target_ssim', NaN, 'target_nmse', NaN, ...
    'target_ee', NaN, 'asm_kwave_pcc', NaN, 'best_z_mm', NaN, ...
    'exit_amp_cv', NaN, 'exit_amp_min_ratio', NaN, 'multi_factor_r2', NaN, ...
    'local_std_amp_corr', NaN, 'edge_dist_amp_corr', NaN, ...
    'layer_min', NaN, 'layer_max', NaN, 'thickness_mean_mm', NaN, 'thickness_std_mm', NaN, ...
    'thickness_grad_mean', NaN, 'focus_search_edge_margin_mm', NaN, 'focus_search_near_edge', false);
end

function row = metrics_to_summary_row(metrics)
row = empty_summary_row();
fields = fieldnames(row);
for idx = 1:numel(fields)
    if isfield(metrics, fields{idx})
        row.(fields{idx}) = metrics.(fields{idx});
    end
end
end

function metrics = calc_image_metrics_local(pred_img, target_img)
pred_norm = pred_img / (max(pred_img(:)) + eps);
target_norm = target_img / (max(target_img(:)) + eps);
metrics.pcc = corr2(pred_norm, target_norm);
metrics.ssim = ssim(double(pred_norm), double(target_norm));
metrics.nmse = sum((pred_norm(:) - target_norm(:)).^2) / sum(target_norm(:).^2);
target_mask = target_norm > 0.5;
metrics.ee = sum(pred_norm(target_mask).^2) / (sum(pred_norm(:).^2) + eps);
end

function metrics = empty_image_metrics_local()
metrics = struct('pcc', NaN, 'ssim', NaN, 'nmse', NaN, 'ee', NaN);
end

function r = corr2_safe(x, y)
x = double(x(:));
y = double(y(:));
valid = isfinite(x) & isfinite(y);
if nnz(valid) < 3
    r = NaN;
else
    r = corr(x(valid), y(valid));
end
end

function r2 = fit_exit_amp_linear_r2(thickness, grad_norm, local_std, edge_dist, exit_amp)
X = [ones(numel(exit_amp), 1), thickness(:), grad_norm(:), local_std(:), edge_dist(:)];
y = exit_amp(:);
valid = all(isfinite(X), 2) & isfinite(y);
if nnz(valid) < size(X, 2)
    r2 = NaN;
    return;
end
coef = X(valid, :) \ y(valid);
pred = X(valid, :) * coef;
ss_res = sum((y(valid) - pred).^2);
ss_tot = sum((y(valid) - mean(y(valid))).^2);
r2 = 1 - ss_res / (ss_tot + eps);
end

function n_fast = next_fast_grid_size(n_required)
candidate_sizes = [ ...
    64, 72, 80, 90, 96, 100, 108, 120, 128, 144, 150, 160, 180, 192, ...
    200, 216, 240, 256, 270, 288, 300, 320, 360, 384, 400, 432, ...
    480, 512, 540, 576, 600, 640, 720, 768, 800, 864, 900, 960, 1024];
n_fast = candidate_sizes(find(candidate_sizes >= n_required, 1));
if isempty(n_fast)
    n_fast = 2 ^ nextpow2(n_required);
end
end

function medium_cpu = cast_medium_for_cpu(medium)
medium_cpu = medium;
fields = {'sound_speed', 'density', 'alpha_coeff'};
for idx = 1:numel(fields)
    field_name = fields{idx};
    if isfield(medium_cpu, field_name)
        medium_cpu.(field_name) = double(medium_cpu.(field_name));
    end
end
end

function source_cpu = cast_source_for_cpu(source)
source_cpu = source;
if isfield(source_cpu, 'p_mask')
    source_cpu.p_mask = double(source_cpu.p_mask);
end
if isfield(source_cpu, 'p')
    source_cpu.p = double(source_cpu.p);
end
end

function sensor_cpu = cast_sensor_for_cpu(sensor)
sensor_cpu = sensor;
if isfield(sensor_cpu, 'mask')
    sensor_cpu.mask = double(sensor_cpu.mask);
end
end

function p_complex_vec = demodulate_kwave_pressure(p_time, t_record, f0)
demod_ref = exp(-1i * 2 * pi * f0 * t_record(:));
p_complex_vec = (p_time * demod_ref) ./ numel(t_record);
end

function value = getenv_default(name, default_value)
value = getenv(name);
if isempty(value)
    value = default_value;
end
end

function ensure_dir(path_value)
if ~exist(path_value, 'dir')
    mkdir(path_value);
end
end

function label = sanitize_label(label)
label = regexprep(char(label), '[^A-Za-z0-9_.+-]', '_');
end

function write_json_file(path_value, data)
fid = fopen(path_value, 'w');
if fid < 0
    error('modulation_law_dataset_sweep:WriteFailed', 'Could not open %s', path_value);
end
cleanup = onCleanup(@() fclose(fid));
try
    json_text = jsonencode(data, 'PrettyPrint', true);
catch
    json_text = jsonencode(data);
end
fwrite(fid, json_text, 'char');
end
