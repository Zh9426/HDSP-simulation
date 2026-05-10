clear; close all; clc;

script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(script_dir);
addpath(repo_root);

cfg = board_compare_config(script_dir, repo_root);
rng(cfg.rng_seed);

if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end
if ~exist(cfg.transport_dir, 'dir')
    mkdir(cfg.transport_dir);
end

fprintf('==================================================\n');
fprintf('Phase-board construction comparison\n');
fprintf('Branch scope: phase-board modulation diagnosis\n');
fprintf('Grid: %d x %d | dx %.4f mm | z target %.2f mm from board exit\n', ...
    cfg.Nx, cfg.Ny, cfg.dx * 1e3, cfg.z_target_dist * 1e3);
fprintf('Main IASA epochs: %d | pure BIASA epochs: %d\n', cfg.main_iasa_epochs, cfg.biasa_epochs);
fprintf('Outputs: %s\n', cfg.output_dir);
fprintf('==================================================\n');

target = build_scaffold_target(cfg);
propagator = make_board_compare_asm_propagator(cfg);

seed_phase = zeros(cfg.Nx, cfg.Ny);
seed_phase(target.source_mask) = 2 * pi * rand(nnz(target.source_mask), 1);

fprintf('\n[0] Building BIASA initial phase for direct discretization baseline.\n');
continuous_initial = run_continuous_wiasa(seed_phase, target.amp_design, target.source_mask, propagator, cfg);

phase_cases = struct([]);
phase_cases = append_case(phase_cases, build_direct_discrete_case(continuous_initial.phase, target, propagator, cfg));

if cfg.run_python_case
    python_case = build_python_iasa_case(target, propagator, cfg);
    phase_cases = append_case(phase_cases, python_case);
else
    fprintf('\n[2] Python+IASA case skipped by HDSP_BOARD_COMPARE_RUN_PYTHON_CASE=0.\n');
end

phase_cases = append_case(phase_cases, build_pure_biasa_case(seed_phase, target, propagator, cfg));

for idx = 1:numel(phase_cases)
    phase_cases(idx).asm_metrics = calculate_compare_metrics(phase_cases(idx).asm_amp_norm, target.amp_norm, target.mask);
    phase_cases(idx).phase_metrics = calculate_phase_summary(phase_cases(idx).phase, target.source_mask);
end

for idx = 1:numel(phase_cases)
    if cfg.dry_run
        phase_cases(idx).kwave = make_dry_kwave_case(phase_cases(idx), target, cfg);
    else
        phase_cases(idx).kwave = run_full_board_kwave_case(phase_cases(idx), target, cfg);
    end
    phase_cases(idx).kwave_metrics = calculate_compare_metrics( ...
        phase_cases(idx).kwave.target_amp_norm, target.amp_norm, target.mask);
end

results = struct();
results.cfg = cfg;
results.target = target;
results.phase_cases = phase_cases;
results.created_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

save(fullfile(cfg.output_dir, 'board_construction_comparison_results.mat'), 'results', '-v7.3');
write_board_comparison_summary(results);
plot_board_comparison_results(results);

fprintf('\n==================================================\n');
fprintf('Phase-board construction comparison summary\n');
for idx = 1:numel(phase_cases)
    m = phase_cases(idx).kwave_metrics;
    fprintf('%-34s | PCC %.4f | SSIM %.4f | NMSE %.4f | EE %.2f%% | best z %.2f mm\n', ...
        phase_cases(idx).label, m.pcc, m.ssim, m.nmse, m.energy_efficiency * 100, ...
        phase_cases(idx).kwave.best_z_from_board_exit_mm);
end
fprintf('Outputs written to: %s\n', cfg.output_dir);
fprintf('==================================================\n');

function cfg = board_compare_config(script_dir, repo_root)
cfg = struct();
cfg.Nx = env_number('HDSP_BOARD_COMPARE_NX', 512);
cfg.Ny = cfg.Nx;
cfg.Lx = 65e-3;
cfg.Ly = cfg.Lx;
cfg.dx = cfg.Lx / cfg.Nx;
cfg.dy = cfg.dx;
cfg.dz = cfg.dx;

cfg.f0 = 4.5e6;
cfg.c_water = 1480;
cfg.c_board = 2430;
cfg.density_water = 997;
cfg.density_board = 1100;
cfg.alpha_coeff_water = 0.002;
cfg.alpha_power_water = 1.5;
cfg.alpha_coeff_board = 1.5;
cfg.lambda_water = cfg.c_water / cfg.f0;

cfg.z_target_dist = 16e-3;
cfg.source_radius = 32e-3;
cfg.source_pressure_pa = 1.0e5;
cfg.min_base_layers = 2;
cfg.pad_factor = 2;
cfg.rng_seed = 9426;
cfg.cfl = 0.3;
cfg.pml_size = 10;
cfg.source_z_offset_after_pml = 5;
cfg.exit_probe_after_board_m = 2e-3;
cfg.focus_scan_offsets_m = parse_mm_offsets(getenv_default('HDSP_BOARD_COMPARE_SCAN_OFFSETS_MM', '0'));

cfg.main_iasa_epochs = env_number('HDSP_BOARD_COMPARE_MAIN_EPOCHS', 150);
cfg.biasa_epochs = env_number('HDSP_BOARD_COMPARE_BIASA_EPOCHS', 450);
cfg.initial_wiasa_epochs = env_number('HDSP_BOARD_COMPARE_INITIAL_EPOCHS', 150);
cfg.iasa_beta = 0.60;
cfg.iasa_anchor_eta = 1.0;
cfg.iasa_dark_weight = 0.0;
cfg.iasa_halo_weight = 0.05;
cfg.iasa_target_gain_limit = 10.0;
cfg.iasa_uniformity_enabled = true;
cfg.iasa_uniformity_beta = 0.30;
cfg.iasa_uniformity_gain_limit = 2.5;

cfg.run_python_case = env_flag('HDSP_BOARD_COMPARE_RUN_PYTHON_CASE', true);
cfg.reuse_python_output = env_flag('HDSP_BOARD_COMPARE_REUSE_PYTHON_OUTPUT', false);
cfg.transport_dir = 'C:\Users\Zh89\Desktop\transport';
cfg.python_input_mat = fullfile(cfg.transport_dir, 'target_for_python.mat');
cfg.python_output_mat = fullfile(cfg.transport_dir, 'dl_phase_init.mat');
cfg.python_script = fullfile(script_dir, 'helpers', 'PANN_Holography.py');
cfg.python_executable = getenv_default('HDSP_BOARD_COMPARE_PYTHON', 'C:\Users\Zh89\anaconda3\envs\dlmia-gpu\python.exe');
cfg.python_epochs = env_number('HDSP_BOARD_COMPARE_PYTHON_EPOCHS', 10000);
cfg.python_learning_rate = 0.06;
cfg.python_min_epochs = 6500;
cfg.python_early_stop_patience = 4200;
cfg.python_rng_seed = cfg.rng_seed;
cfg.python_lr_restart_cycle = 5000;
cfg.python_lr_restart_decay = 0.82;
cfg.python_lr_min_ratio = 0.05;
cfg.python_z_constraint_offsets_m = 0;
cfg.target_threshold_norm = 0.60;
cfg.low_quantile_goal = 0.88;
cfg.target_mean_amp_goal_ratio = 0.12;

cfg.output_dir = fullfile(script_dir, 'outputs');
cfg.repo_root = repo_root;
cfg.script_dir = script_dir;
cfg.git_commit_short = get_git_commit_short(repo_root);
cfg.dry_run = env_flag('HDSP_BOARD_COMPARE_DRY_RUN', false);
end

function target = build_scaffold_target(cfg)
x = (-cfg.Nx/2:cfg.Nx/2-1) * cfg.dx;
y = (-cfg.Ny/2:cfg.Ny/2-1) * cfg.dy;
[Y, X] = meshgrid(y, x);

strut_width = 1.0e-3;
pore_size = 3.0e-3;
pitch = strut_width + pore_size;
mask_x = mod(X + cfg.Lx/2, pitch) < strut_width;
mask_y = mod(Y + cfg.Ly/2, pitch) < strut_width;
scaffold_raw = mask_x | mask_y;
target_radius = 15e-3;
circle_mask = (X.^2 + Y.^2) <= target_radius^2;
raw_mask = scaffold_raw & circle_mask;

amp = imgaussfilt(double(raw_mask), 0.5);
amp = amp / (max(amp(:)) + eps);

thermal_alpha_guess = 0.15 / (1100 * 1800);
thermal_exposure_guess = 0.35;
thermal_diff_len = sqrt(4 * thermal_alpha_guess * thermal_exposure_guess);
thermal_sigma_px = max(0.8, 0.35 * thermal_diff_len / cfg.dx);
design_blur = imgaussfilt(double(raw_mask), thermal_sigma_px);
amp_design = double(design_blur > 0.58);
amp_design = imgaussfilt(amp_design, 0.45);
amp_design = amp_design / (max(amp_design(:)) + eps);

source_mask = (X.^2 + Y.^2) <= cfg.source_radius^2;

target.x = x;
target.y = y;
target.X = X;
target.Y = Y;
target.amp = amp;
target.amp_norm = amp / (max(amp(:)) + eps);
target.amp_design = amp_design;
target.mask = amp > 0.5;
target.source_mask = source_mask;
target.raw_mask = raw_mask;
target.thermal_sigma_px = thermal_sigma_px;
end

function propagator = make_board_compare_asm_propagator(cfg)
Nx_pad = cfg.Nx * cfg.pad_factor;
Ny_pad = cfg.Ny * cfg.pad_factor;
Lx_pad = cfg.Lx * cfg.pad_factor;
Ly_pad = cfg.Ly * cfg.pad_factor;
dkx = 2 * pi / Lx_pad;
dky = 2 * pi / Ly_pad;
kx = (-Nx_pad/2:Nx_pad/2-1) * dkx;
ky = (-Ny_pad/2:Ny_pad/2-1) * dky;
[Ky, Kx] = meshgrid(ky, kx);

k0 = 2 * pi * cfg.f0 / cfg.c_water;
Kz_sq = k0^2 - Kx.^2 - Ky.^2;
propagating = Kz_sq > 0;
Kz = zeros(size(Kz_sq));
Kz(propagating) = sqrt(Kz_sq(propagating));

H_forward = zeros(size(Kz_sq));
H_forward(propagating) = exp(1i * Kz(propagating) * cfg.z_target_dist);

propagator.Nx_pad = Nx_pad;
propagator.Ny_pad = Ny_pad;
propagator.center_idx = cfg.Nx/2+1:cfg.Nx/2+cfg.Nx;
propagator.H_forward = H_forward;
propagator.H_backward = conj(H_forward);
end

function case_out = build_direct_discrete_case(initial_phase, target, propagator, cfg)
fprintf('\n[1] Direct discretization from BIASA initial phase.\n');
phase_step = board_phase_step(cfg);
[phase_projected, layer_map, phase_bias] = project_phase_to_board( ...
    initial_phase, phase_step, cfg.min_base_layers, target.source_mask, 0, true);
case_out = make_board_case('direct_discrete_from_biasa_initial', phase_projected, layer_map, phase_step, phase_bias, target, propagator, cfg);
case_out.optimizer_metrics = struct( ...
    'mode', 'continuous_wiasa_initial_then_one_shot_board_projection', ...
    'initial_epochs', cfg.initial_wiasa_epochs, ...
    'board_projection_in_loop', false);
end

function case_out = build_python_iasa_case(target, propagator, cfg)
fprintf('\n[2] Python initial phase + in-loop IASA board projection.\n');
export_python_transport_input(cfg, target);
if ~cfg.reuse_python_output || ~exist(cfg.python_output_mat, 'file')
    wait_for_python_phase_output(cfg);
else
    fprintf('Reusing existing Python output: %s\n', cfg.python_output_mat);
end

data = load(cfg.python_output_mat);
if ~isfield(data, 'optimal_initial_phase')
    error('Python output lacks optimal_initial_phase: %s', cfg.python_output_mat);
end

phase_bias_seed = 0;
if isfield(data, 'optimal_phase_bias') && ~isempty(data.optimal_phase_bias)
    phase_bias_seed = double(data.optimal_phase_bias(1));
end
python_phase = wrap_phase_local(double(data.optimal_initial_phase));
python_phase(~target.source_mask) = 0;

options = struct('epochs', cfg.main_iasa_epochs, 'phase_bias_seed', phase_bias_seed, ...
    'anchor_eta', cfg.iasa_anchor_eta, 'use_dither', true);
iasa_result = run_board_constrained_iasa(python_phase, target.amp_design, target.source_mask, propagator, cfg, options);
case_out = make_board_case('python_iasa_inloop_board', iasa_result.phase, iasa_result.layer_map, ...
    iasa_result.phase_step, iasa_result.phase_bias, target, propagator, cfg);
case_out.history = iasa_result.history;
case_out.optimizer_metrics = iasa_result.optimizer_metrics;
case_out.optimizer_metrics.python_transport_file = cfg.python_output_mat;
end

function case_out = build_pure_biasa_case(seed_phase, target, propagator, cfg)
fprintf('\n[3] Pure BIASA in-loop board construction.\n');
options = struct('epochs', cfg.biasa_epochs, 'phase_bias_seed', 0, ...
    'anchor_eta', cfg.iasa_anchor_eta, 'use_dither', true);
biasa_result = run_board_constrained_iasa(seed_phase, target.amp_design, target.source_mask, propagator, cfg, options);
case_out = make_board_case('pure_biasa_inloop_board', biasa_result.phase, biasa_result.layer_map, ...
    biasa_result.phase_step, biasa_result.phase_bias, target, propagator, cfg);
case_out.history = biasa_result.history;
case_out.optimizer_metrics = biasa_result.optimizer_metrics;
end

function result = run_continuous_wiasa(initial_phase, target_amp, source_mask, propagator, cfg)
phase_now = wrap_phase_local(initial_phase);
phase_now(~source_mask) = 0;
target_pad = zeros(propagator.Nx_pad, propagator.Ny_pad);
target_pad(propagator.center_idx, propagator.center_idx) = target_amp;
line_mask_pad = target_pad > 0.5;
dark_mask_pad = ~line_mask_pad;
weight_pad = 0.05 + target_pad * 1.95;

best_score = -inf;
best_phase = phase_now;
history = zeros(cfg.initial_wiasa_epochs, 8);

for epoch = 1:cfg.initial_wiasa_epochs
    source_pad = zeros(propagator.Nx_pad, propagator.Ny_pad);
    source_crop = exp(1i * phase_now);
    source_crop(~source_mask) = 0;
    source_pad(propagator.center_idx, propagator.center_idx) = source_crop;

    target_field = fftshift(ifft2(ifftshift(fftshift(fft2(ifftshift(source_pad))) .* propagator.H_forward)));
    rec_amp = abs(target_field);
    peak_val = max(rec_amp(line_mask_pad));
    if peak_val == 0
        peak_val = max(rec_amp(:));
    end
    rec_amp_norm = rec_amp / (peak_val + eps);

    if epoch > 5
        correction = (target_pad(line_mask_pad) ./ (rec_amp_norm(line_mask_pad) + 1e-6)) .^ cfg.iasa_beta;
        if cfg.iasa_uniformity_enabled
            target_vals = rec_amp_norm(line_mask_pad);
            target_level = median(target_vals(:));
            uniformity_correction = (target_level ./ (target_vals + 1e-6)) .^ cfg.iasa_uniformity_beta;
            gain_limit = cfg.iasa_uniformity_gain_limit;
            uniformity_correction = min(max(uniformity_correction, 1 / gain_limit), gain_limit);
            correction = correction .* uniformity_correction;
        end
        weight_pad(line_mask_pad) = weight_pad(line_mask_pad) .* correction;
        weight_pad(weight_pad > cfg.iasa_target_gain_limit) = cfg.iasa_target_gain_limit;
        weight_pad(dark_mask_pad) = cfg.iasa_dark_weight;
    end

    constrained_target = weight_pad .* exp(1i * angle(target_field));
    source_back = fftshift(ifft2(ifftshift(fftshift(fft2(ifftshift(constrained_target))) .* propagator.H_backward)));
    phase_now = wrap_phase_local(angle(source_back(propagator.center_idx, propagator.center_idx)));
    phase_now(~source_mask) = 0;

    focus_crop = rec_amp_norm(propagator.center_idx, propagator.center_idx);
    scores = quick_amp_scores(focus_crop, target_amp, target_amp > 0.5);
    history(epoch, :) = scores;
    if scores(8) > best_score
        best_score = scores(8);
        best_phase = phase_now;
    end
end

focus = compute_focus_from_phase(best_phase, source_mask, propagator);
result.phase = best_phase;
result.asm_amp = focus.amp;
result.asm_amp_norm = focus.amp_norm;
result.history = history;
result.best_loop_quality_score = best_score;
end

function result = run_board_constrained_iasa(initial_phase, target_amp, source_mask, propagator, cfg, options)
phase_step = board_phase_step(cfg);
phase_bias_seed = options.phase_bias_seed;
anchor_eta = options.anchor_eta;
use_dither = options.use_dither;
epochs = options.epochs;

[phase_projected, layer_map, phase_bias_seed] = project_phase_to_board( ...
    initial_phase, phase_step, cfg.min_base_layers, source_mask, phase_bias_seed, use_dither);
phase_anchor = phase_projected;

target_pad = zeros(propagator.Nx_pad, propagator.Ny_pad);
target_pad(propagator.center_idx, propagator.center_idx) = target_amp;
line_mask_pad = target_pad > 0.5;
dark_mask_pad = ~line_mask_pad;
weight_pad = 0.05 + target_pad * 1.95;

history = zeros(epochs, 8);
best_score = -inf;
best_epoch = 0;
best_layer_map = layer_map;
best_phase_bias = phase_bias_seed;

for epoch = 1:epochs
    source_pad = zeros(propagator.Nx_pad, propagator.Ny_pad);
    source_crop = exp(1i * phase_projected);
    source_crop(~source_mask) = 0;
    source_pad(propagator.center_idx, propagator.center_idx) = source_crop;

    target_field = fftshift(ifft2(ifftshift(fftshift(fft2(ifftshift(source_pad))) .* propagator.H_forward)));
    rec_amp = abs(target_field);
    peak_val = max(rec_amp(line_mask_pad));
    if peak_val == 0
        peak_val = max(rec_amp(:));
    end
    rec_amp_norm = rec_amp / (peak_val + eps);

    if epoch > 5
        correction = (target_pad(line_mask_pad) ./ (rec_amp_norm(line_mask_pad) + 1e-6)) .^ cfg.iasa_beta;
        if cfg.iasa_uniformity_enabled
            target_vals = rec_amp_norm(line_mask_pad);
            target_level = median(target_vals(:));
            uniformity_correction = (target_level ./ (target_vals + 1e-6)) .^ cfg.iasa_uniformity_beta;
            gain_limit = cfg.iasa_uniformity_gain_limit;
            uniformity_correction = min(max(uniformity_correction, 1 / gain_limit), gain_limit);
            correction = correction .* uniformity_correction;
        end
        weight_pad(line_mask_pad) = weight_pad(line_mask_pad) .* correction;
        weight_pad(weight_pad > cfg.iasa_target_gain_limit) = cfg.iasa_target_gain_limit;
        weight_pad(dark_mask_pad) = cfg.iasa_dark_weight;
    end

    constrained_target = weight_pad .* exp(1i * angle(target_field));
    source_back = fftshift(ifft2(ifftshift(fftshift(fft2(ifftshift(constrained_target))) .* propagator.H_backward)));
    phase_candidate = angle(source_back(propagator.center_idx, propagator.center_idx));

    [phase_projected_raw, ~, phase_bias_seed] = project_phase_to_board( ...
        phase_candidate, phase_step, cfg.min_base_layers, source_mask, phase_bias_seed, use_dither);

    if anchor_eta < 1
        blended_complex = (1 - anchor_eta) .* exp(1i * phase_anchor) + anchor_eta .* exp(1i * phase_projected_raw);
        blended_phase = angle(blended_complex);
    else
        blended_phase = phase_projected_raw;
    end

    [phase_projected, layer_map, phase_bias_seed] = project_phase_to_board( ...
        blended_phase, phase_step, cfg.min_base_layers, source_mask, phase_bias_seed, use_dither);

    focus_crop = rec_amp_norm(propagator.center_idx, propagator.center_idx);
    scores = quick_amp_scores(focus_crop, target_amp, target_amp > 0.5);
    history(epoch, :) = scores;
    if scores(8) > best_score
        best_score = scores(8);
        best_epoch = epoch;
        best_layer_map = layer_map;
        best_phase_bias = phase_bias_seed;
    end
end

final_phase = mod(best_layer_map * phase_step, 2 * pi);
final_phase(~source_mask) = 0;
focus = compute_focus_from_phase(final_phase, source_mask, propagator);

result.phase = final_phase;
result.layer_map = best_layer_map;
result.phase_step = phase_step;
result.phase_bias = best_phase_bias;
result.asm_amp = focus.amp;
result.asm_amp_norm = focus.amp_norm;
result.history = history;
result.optimizer_metrics = struct( ...
    'configured_epochs', epochs, ...
    'selected_epoch', best_epoch, ...
    'best_loop_quality_score', best_score, ...
    'board_projection_in_loop', true, ...
    'anchor_eta', anchor_eta, ...
    'use_dither', use_dither);
end

function case_out = make_board_case(label, phase_map, layer_map, phase_step, phase_bias, target, propagator, cfg)
focus = compute_focus_from_phase(phase_map, target.source_mask, propagator);
thickness_map = double(layer_map) * cfg.dz;
[grad_x, grad_y] = gradient(thickness_map, cfg.dx, cfg.dy);

case_out = struct();
case_out.label = label;
case_out.phase = phase_map;
case_out.layer_map = layer_map;
case_out.phase_step = phase_step;
case_out.phase_bias = phase_bias;
case_out.thickness_map = thickness_map;
case_out.thickness_grad_norm = hypot(grad_x, grad_y);
case_out.asm_amp = focus.amp;
case_out.asm_amp_norm = focus.amp_norm;
case_out.asm_field = focus.field;
case_out.history = [];
case_out.optimizer_metrics = struct();
end

function kwave = run_full_board_kwave_case(case_now, target, cfg)
if exist('kWaveGrid', 'file') ~= 2 || exist('kspaceFirstOrder3D', 'file') ~= 2
    error('k-Wave is not on the MATLAB path. Add k-Wave before running board comparison.');
end

fprintf('\n[%s] Full physical-board k-Wave run.\n', case_now.label);
pml_size = cfg.pml_size;
source_z_idx = pml_size + cfg.source_z_offset_after_pml;
z_board_start_idx = source_z_idx + 1;
max_layers = max(case_now.layer_map(:));
z_board_exit_idx = z_board_start_idx + max_layers;
z_exit_probe_idx = z_board_exit_idx + max(1, round(cfg.exit_probe_after_board_m / cfg.dz));
target_plane_indices = z_board_exit_idx + round((cfg.z_target_dist + cfg.focus_scan_offsets_m) / cfg.dz);
z_scan_start = min(target_plane_indices);
z_scan_end = max(target_plane_indices);
Nz_required = max([z_exit_probe_idx, z_scan_end]) + pml_size + 12;
Nz = next_fast_grid_size(Nz_required);

fprintf('  Nz required=%d -> using %d | max layers=%d | scan planes=%d\n', ...
    Nz_required, Nz, max_layers, numel(target_plane_indices));

kgrid = kWaveGrid(cfg.Nx, cfg.dx, cfg.Ny, cfg.dy, Nz, cfg.dz);
medium.sound_speed = cfg.c_water * ones(cfg.Nx, cfg.Ny, Nz, 'single');
medium.density = cfg.density_water * ones(cfg.Nx, cfg.Ny, Nz, 'single');
medium.alpha_coeff = cfg.alpha_coeff_water * ones(cfg.Nx, cfg.Ny, Nz, 'single');
medium.alpha_power = cfg.alpha_power_water;

for row = 1:cfg.Nx
    for col = 1:cfg.Ny
        n_layers = case_now.layer_map(row, col);
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
source.p_mask(:, :, source_z_idx) = single(target.source_mask);
t_vec = reshape(kgrid.t_array, 1, []);
source_sig = cfg.source_pressure_pa * sin(2 * pi * cfg.f0 .* t_vec);
ramp_pts = min(kgrid.Nt, max(1, round(2 / cfg.f0 / kgrid.dt)));
source.p = single(source_sig .* [linspace(0, 1, ramp_pts), ones(1, kgrid.Nt - ramp_pts)]);
source.p_mode = 'dirichlet';

sensor.mask = zeros(cfg.Nx, cfg.Ny, Nz, 'single');
sensor.mask(:, :, z_exit_probe_idx) = 1;
for idx = 1:numel(target_plane_indices)
    sensor.mask(:, :, target_plane_indices(idx)) = 1;
end
sensor.record = {'p', 'p_max'};
sensor.record_start_index = max(1, kgrid.Nt - round(3 / cfg.f0 / kgrid.dt));

input_args = {'PMLInside', true, 'PMLSize', pml_size, 'PlotPML', false, 'PlotSim', false, 'DataCast', 'gpuArray-single'};
using_gpu = true;
try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch gpu_error
    fprintf('  GPU path failed: %s\n', gpu_error.message);
    fprintf('  Falling back to CPU with double medium/source/sensor arrays.\n');
    using_gpu = false;
    sensor_data = kspaceFirstOrder3D(kgrid, cast_medium_cpu(medium), cast_source_cpu(source), ...
        cast_sensor_cpu(sensor), input_args{1:end-2});
end

p_max = gather(sensor_data.p_max);
p_amp_volume = zeros(cfg.Nx, cfg.Ny, Nz);
p_amp_volume(sensor.mask ~= 0) = p_max;

p_time = gather(sensor_data.p);
t_record = kgrid.t_array(sensor.record_start_index:end);
p_complex_vec = demodulate_kwave_pressure(p_time, t_record, cfg.f0);
p_complex_volume = complex(zeros(cfg.Nx, cfg.Ny, Nz));
p_complex_volume(sensor.mask ~= 0) = p_complex_vec;

clear sensor_data p_time p_max;
if using_gpu
    try
        reset(gpuDevice);
    catch
    end
end

best_idx = 1;
best_pcc = -inf;
plane_records = repmat(struct('z_from_board_exit_mm', NaN, 'pcc', NaN, 'ssim', NaN, 'nmse', NaN, 'energy_efficiency', NaN), numel(target_plane_indices), 1);
for idx = 1:numel(target_plane_indices)
    plane_idx = target_plane_indices(idx);
    amp_now = p_amp_volume(:, :, plane_idx);
    amp_now_norm = amp_now / (max(amp_now(:)) + eps);
    metrics_now = calculate_compare_metrics(amp_now_norm, target.amp_norm, target.mask);
    plane_records(idx).z_from_board_exit_mm = (plane_idx - z_board_exit_idx) * cfg.dz * 1e3;
    plane_records(idx).pcc = metrics_now.pcc;
    plane_records(idx).ssim = metrics_now.ssim;
    plane_records(idx).nmse = metrics_now.nmse;
    plane_records(idx).energy_efficiency = metrics_now.energy_efficiency;
    if metrics_now.pcc > best_pcc
        best_pcc = metrics_now.pcc;
        best_idx = idx;
    end
end

best_plane_idx = target_plane_indices(best_idx);
target_amp = p_amp_volume(:, :, best_plane_idx);
target_complex = p_complex_volume(:, :, best_plane_idx);
exit_complex = p_complex_volume(:, :, z_exit_probe_idx);
exit_amp = abs(exit_complex);

kwave = struct();
kwave.Nz = Nz;
kwave.source_z_idx = source_z_idx;
kwave.z_board_start_idx = z_board_start_idx;
kwave.z_board_exit_idx = z_board_exit_idx;
kwave.z_exit_probe_idx = z_exit_probe_idx;
kwave.target_plane_indices = target_plane_indices;
kwave.best_target_plane_idx = best_plane_idx;
kwave.best_z_from_board_exit_mm = (best_plane_idx - z_board_exit_idx) * cfg.dz * 1e3;
kwave.plane_records = plane_records;
kwave.target_amp = target_amp;
kwave.target_amp_norm = target_amp / (max(target_amp(:)) + eps);
kwave.target_complex = target_complex;
kwave.target_phase = angle(target_complex);
kwave.exit_complex = exit_complex;
kwave.exit_amp = exit_amp;
kwave.exit_amp_norm = exit_amp / (max(exit_amp(:)) + eps);
kwave.exit_phase = angle(exit_complex);
kwave.exit_amp_cv = std(exit_amp(target.source_mask)) / (mean(exit_amp(target.source_mask)) + eps);
kwave.exit_amp_min_ratio = min(exit_amp(target.source_mask)) / (max(exit_amp(target.source_mask)) + eps);
kwave.focus_scan_offsets_m = cfg.focus_scan_offsets_m;
kwave.z_scan_start = z_scan_start;
kwave.z_scan_end = z_scan_end;
end

function kwave = make_dry_kwave_case(case_now, target, cfg)
fprintf('\n[%s] Dry run: using ASM field as k-Wave placeholder.\n', case_now.label);
target_amp = case_now.asm_amp;
target_amp_norm = target_amp / (max(target_amp(:)) + eps);
exit_complex = exp(1i * case_now.phase) .* target.source_mask;
exit_amp = abs(exit_complex);
kwave = struct();
kwave.Nz = NaN;
kwave.source_z_idx = NaN;
kwave.z_board_start_idx = NaN;
kwave.z_board_exit_idx = NaN;
kwave.z_exit_probe_idx = NaN;
kwave.target_plane_indices = NaN;
kwave.best_target_plane_idx = NaN;
kwave.best_z_from_board_exit_mm = cfg.z_target_dist * 1e3;
kwave.plane_records = struct('z_from_board_exit_mm', kwave.best_z_from_board_exit_mm, ...
    'pcc', NaN, 'ssim', NaN, 'nmse', NaN, 'energy_efficiency', NaN);
kwave.target_amp = target_amp;
kwave.target_amp_norm = target_amp_norm;
kwave.target_complex = case_now.asm_field;
kwave.target_phase = angle(case_now.asm_field);
kwave.exit_complex = exit_complex;
kwave.exit_amp = exit_amp;
kwave.exit_amp_norm = exit_amp / (max(exit_amp(:)) + eps);
kwave.exit_phase = angle(exit_complex);
kwave.exit_amp_cv = std(exit_amp(target.source_mask)) / (mean(exit_amp(target.source_mask)) + eps);
kwave.exit_amp_min_ratio = min(exit_amp(target.source_mask)) / (max(exit_amp(target.source_mask)) + eps);
kwave.focus_scan_offsets_m = cfg.focus_scan_offsets_m;
kwave.z_scan_start = NaN;
kwave.z_scan_end = NaN;
end

function export_python_transport_input(cfg, target)
imag_target = target.amp;
imag_target_design = target.amp_design;
Nx = cfg.Nx;
Ny = cfg.Ny;
Lx = cfg.Lx;
lambda_water = cfg.lambda_water;
z_target_dist = cfg.z_target_dist;
dx = cfg.dx;
dz = cfg.dz;
f0 = cfg.f0;
c_water = cfg.c_water;
c_board = cfg.c_board;
thermal_sigma_px = target.thermal_sigma_px;
min_base_layers = cfg.min_base_layers;
target_threshold_norm = cfg.target_threshold_norm;
low_quantile_goal = cfg.low_quantile_goal;
target_mean_amp_goal_ratio = cfg.target_mean_amp_goal_ratio;
python_z_constraint_offsets_m = cfg.python_z_constraint_offsets_m;
branch_output_dir = cfg.output_dir;
python_epochs = cfg.python_epochs;
python_learning_rate = cfg.python_learning_rate;
python_min_epochs = cfg.python_min_epochs;
python_early_stop_patience = cfg.python_early_stop_patience;
python_rng_seed = cfg.python_rng_seed;
python_lr_restart_cycle = cfg.python_lr_restart_cycle;
python_lr_restart_decay = cfg.python_lr_restart_decay;
python_lr_min_ratio = cfg.python_lr_min_ratio;

save(cfg.python_input_mat, 'imag_target', 'imag_target_design', 'Nx', 'Ny', 'Lx', ...
    'lambda_water', 'z_target_dist', 'dx', 'dz', 'f0', 'c_water', ...
    'c_board', 'thermal_sigma_px', 'min_base_layers', ...
    'target_threshold_norm', 'low_quantile_goal', ...
    'target_mean_amp_goal_ratio', 'python_z_constraint_offsets_m', ...
    'branch_output_dir', 'python_epochs', 'python_learning_rate', ...
    'python_min_epochs', 'python_early_stop_patience', 'python_rng_seed', ...
    'python_lr_restart_cycle', 'python_lr_restart_decay', 'python_lr_min_ratio');

fprintf('  Python transport input: %s\n', cfg.python_input_mat);
end

function wait_for_python_phase_output(cfg)
command = sprintf('"%s" "%s"', cfg.python_executable, cfg.python_script);
fprintf('\n==================================================\n');
fprintf('Python optimizer input written.\n');
fprintf('Run this command in PowerShell, then return to MATLAB and press any key:\n%s\n', command);
fprintf('Expected output: %s\n', cfg.python_output_mat);
fprintf('==================================================\n\n');
pause;
if ~exist(cfg.python_output_mat, 'file')
    error('Python optimizer output not found: %s', cfg.python_output_mat);
end
end

function write_board_comparison_summary(results)
summary = struct();
summary.created_at = results.created_at;
summary.output_dir = results.cfg.output_dir;
summary.git_commit_short = results.cfg.git_commit_short;
summary.cases = struct([]);

txt_path = fullfile(results.cfg.output_dir, 'summary.txt');
json_path = fullfile(results.cfg.output_dir, 'summary.json');
csv_path = fullfile(results.cfg.output_dir, 'metrics_table.csv');

fid = fopen(txt_path, 'w');
if fid < 0
    error('Cannot write summary: %s', txt_path);
end
fprintf(fid, 'Phase-board construction comparison\n');
fprintf(fid, 'Created at: %s\n', results.created_at);
fprintf(fid, 'Output directory: %s\n\n', results.cfg.output_dir);
fprintf(fid, 'No curing module is used. k-Wave simulates a plane source passing through the physical board.\n\n');

csv_fid = fopen(csv_path, 'w');
if csv_fid < 0
    error('Cannot write CSV: %s', csv_path);
end
fprintf(csv_fid, 'label,asm_pcc,kwave_pcc,kwave_ssim,kwave_nmse,kwave_ee,best_z_mm,exit_amp_cv,exit_amp_min_ratio,layer_min,layer_max,thickness_mean_mm,thickness_std_mm\n');

for idx = 1:numel(results.phase_cases)
    c = results.phase_cases(idx);
    asm = c.asm_metrics;
    km = c.kwave_metrics;
    fprintf(fid, '[%s]\n', c.label);
    fprintf(fid, 'ASM PCC/SSIM/NMSE/EE: %.6f / %.6f / %.6f / %.6f\n', asm.pcc, asm.ssim, asm.nmse, asm.energy_efficiency);
    fprintf(fid, 'k-Wave PCC/SSIM/NMSE/EE: %.6f / %.6f / %.6f / %.6f\n', km.pcc, km.ssim, km.nmse, km.energy_efficiency);
    fprintf(fid, 'best_z_from_board_exit_mm: %.6f\n', c.kwave.best_z_from_board_exit_mm);
    fprintf(fid, 'exit_amp_cv: %.6f\n', c.kwave.exit_amp_cv);
    fprintf(fid, 'exit_amp_min_ratio: %.6f\n', c.kwave.exit_amp_min_ratio);
    fprintf(fid, 'layer_min_max: %d / %d\n', min(c.layer_map(:)), max(c.layer_map(:)));
    fprintf(fid, 'thickness_mean_std_mm: %.6f / %.6f\n\n', mean(c.thickness_map(:)) * 1e3, std(c.thickness_map(:)) * 1e3);

    summary.cases(idx).label = c.label;
    summary.cases(idx).asm = asm;
    summary.cases(idx).kwave = km;
    summary.cases(idx).best_z_from_board_exit_mm = c.kwave.best_z_from_board_exit_mm;
    summary.cases(idx).exit_amp_cv = c.kwave.exit_amp_cv;
    summary.cases(idx).exit_amp_min_ratio = c.kwave.exit_amp_min_ratio;
    summary.cases(idx).layer_min = min(c.layer_map(:));
    summary.cases(idx).layer_max = max(c.layer_map(:));
    summary.cases(idx).thickness_mean_mm = mean(c.thickness_map(:)) * 1e3;
    summary.cases(idx).thickness_std_mm = std(c.thickness_map(:)) * 1e3;
    summary.cases(idx).optimizer_metrics = c.optimizer_metrics;

    fprintf(csv_fid, '%s,%.8g,%.8g,%.8g,%.8g,%.8g,%.8g,%.8g,%.8g,%d,%d,%.8g,%.8g\n', ...
        c.label, asm.pcc, km.pcc, km.ssim, km.nmse, km.energy_efficiency, ...
        c.kwave.best_z_from_board_exit_mm, c.kwave.exit_amp_cv, c.kwave.exit_amp_min_ratio, ...
        min(c.layer_map(:)), max(c.layer_map(:)), mean(c.thickness_map(:)) * 1e3, std(c.thickness_map(:)) * 1e3);
end

fclose(fid);
fclose(csv_fid);

fid_json = fopen(json_path, 'w');
if fid_json < 0
    error('Cannot write JSON summary: %s', json_path);
end
fwrite(fid_json, jsonencode(summary, 'PrettyPrint', true));
fclose(fid_json);
end

function plot_board_comparison_results(results)
target = results.target;
cases = results.phase_cases;
out_dir = results.cfg.output_dir;

fig = figure('Color', 'w', 'Position', [40, 40, 1800, 1100]);
tiledlayout(numel(cases) + 1, 4, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile; imagesc(target.x * 1e3, target.y * 1e3, target.amp_norm); axis image; colormap(gca, gray); colorbar; title('Target');
nexttile; imagesc(target.x * 1e3, target.y * 1e3, target.amp_design); axis image; colormap(gca, gray); colorbar; title('Design target');
nexttile; imagesc(target.x * 1e3, target.y * 1e3, target.source_mask); axis image; colormap(gca, gray); colorbar; title('Source aperture');
nexttile; axis off; text(0, 0.85, sprintf('Nx %d | dx %.4f mm', results.cfg.Nx, results.cfg.dx * 1e3), 'FontSize', 11); text(0, 0.68, sprintf('z %.2f mm from board exit', results.cfg.z_target_dist * 1e3), 'FontSize', 11);

for idx = 1:numel(cases)
    c = cases(idx);
    nexttile; imagesc(target.x * 1e3, target.y * 1e3, c.thickness_map * 1e3); axis image; colormap(gca, parula); colorbar; title([c.label, ' thickness']);
    nexttile; imagesc(target.x * 1e3, target.y * 1e3, c.asm_amp_norm); axis image; colormap(gca, hot); colorbar; title(sprintf('ASM PCC %.3f', c.asm_metrics.pcc));
    nexttile; imagesc(target.x * 1e3, target.y * 1e3, c.kwave.exit_amp_norm); axis image; colormap(gca, jet); colorbar; title(sprintf('Exit amp CV %.3f', c.kwave.exit_amp_cv));
    nexttile; imagesc(target.x * 1e3, target.y * 1e3, c.kwave.target_amp_norm); axis image; colormap(gca, jet); colorbar; title(sprintf('Target k-Wave PCC %.3f', c.kwave_metrics.pcc));
end
exportgraphics(fig, fullfile(out_dir, 'board_construction_overview.png'), 'Resolution', 300);
close(fig);

fig2 = figure('Color', 'w', 'Position', [120, 120, 1450, 720]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

mid = round(numel(target.y) / 2);
nexttile;
plot(target.x * 1e3, target.amp_norm(:, mid), 'k-', 'LineWidth', 2); hold on;
for idx = 1:numel(cases)
    plot(target.x * 1e3, cases(idx).kwave.target_amp_norm(:, mid), 'LineWidth', 1.5);
end
grid on; xlabel('x (mm)'); ylabel('Normalized pressure'); title('Target-plane x centerline');
legend(['Target', {cases.label}], 'Interpreter', 'none', 'Location', 'best');

nexttile;
labels = categorical({cases.label}); labels = reordercats(labels, {cases.label});
bar(labels, arrayfun(@(c) c.kwave_metrics.pcc, cases)); ylim([0, 1]); grid on; ylabel('PCC'); title('k-Wave PCC');

nexttile;
bar(labels, arrayfun(@(c) c.kwave_metrics.energy_efficiency * 100, cases)); grid on; ylabel('EE (%)'); title('Target energy efficiency');

nexttile;
bar(labels, arrayfun(@(c) c.kwave.exit_amp_cv, cases)); grid on; ylabel('CV'); title('Exit amplitude CV');

exportgraphics(fig2, fullfile(out_dir, 'centerline_comparison.png'), 'Resolution', 300);
close(fig2);
end

function focus = compute_focus_from_phase(phase_map, source_mask, propagator)
source_field = exp(1i * wrap_phase_local(phase_map));
source_field(~source_mask) = 0;
padded_source = zeros(propagator.Nx_pad, propagator.Ny_pad);
padded_source(propagator.center_idx, propagator.center_idx) = source_field;
target_field = fftshift(ifft2(ifftshift(fftshift(fft2(ifftshift(padded_source))) .* propagator.H_forward)));
field_crop = target_field(propagator.center_idx, propagator.center_idx);
focus.field = field_crop;
focus.amp = abs(field_crop);
focus.amp_norm = focus.amp / (max(focus.amp(:)) + eps);
focus.phase = angle(field_crop);
end

function metrics = calculate_compare_metrics(pred_img, target_img, target_mask)
pred = double(pred_img);
target = double(target_img);
pred = pred / (max(pred(:)) + eps);
target = target / (max(target(:)) + eps);
pred_centered = pred(:) - mean(pred(:));
target_centered = target(:) - mean(target(:));
metrics = struct();
metrics.pcc = sum(pred_centered .* target_centered) / (sqrt(sum(pred_centered.^2) * sum(target_centered.^2)) + eps);
metrics.nmse = sum((pred(:) - target(:)).^2) / (sum(target(:).^2) + eps);
metrics.energy_efficiency = sum(pred(target_mask).^2) / (sum(pred(:).^2) + eps);
vals = pred(target_mask);
metrics.target_mean = mean(vals(:));
metrics.target_cv = std(vals(:)) / (mean(vals(:)) + eps);
if exist('ssim', 'file') == 2
    metrics.ssim = ssim(pred, target);
else
    metrics.ssim = NaN;
end
end

function metrics = calculate_phase_summary(phase_map, source_mask)
phase = wrap_phase_local(double(phase_map));
active = phase(source_mask);
[gx, gy] = phase_gradients(phase);
grad_mag = hypot(gx, gy);
metrics = struct();
metrics.phase_mean_rad = angle(mean(exp(1i * active)));
metrics.phase_resultant_length = abs(mean(exp(1i * active)));
metrics.phase_circular_variance = 1 - metrics.phase_resultant_length;
metrics.phase_gradient_mean_rad = mean(grad_mag(source_mask));
metrics.phase_gradient_p90_rad = prctile(grad_mag(source_mask), 90);
metrics.phase_wrap_fraction = mean(abs(angle(exp(1i * active))) > 0.95 * pi);
end

function [gx, gy] = phase_gradients(phase)
gx = angle(exp(1i * diff(phase, 1, 1)));
gx = [gx; gx(end, :)];
gy = angle(exp(1i * diff(phase, 1, 2)));
gy = [gy, gy(:, end)];
end

function scores = quick_amp_scores(pred_amp, target_amp, target_mask)
pred = pred_amp / (max(pred_amp(:)) + eps);
target = target_amp / (max(target_amp(:)) + eps);
pred_centered = pred(:) - mean(pred(:));
target_centered = target(:) - mean(target(:));
pcc = sum(pred_centered .* target_centered) / (sqrt(sum(pred_centered.^2) * sum(target_centered.^2)) + eps);
nmse = sum((pred(:) - target(:)).^2) / (sum(target(:).^2) + eps);
energy_efficiency = sum(pred(target_mask).^2) / (sum(pred(:).^2) + eps);
target_vals = pred(target_mask);
target_cv = std(target_vals(:)) / (mean(target_vals(:)) + eps);
target_p10 = prctile(target_vals(:), 10);
target_p50 = prctile(target_vals(:), 50);
p10_over_p50 = target_p10 / (target_p50 + eps);
target_peak_over_mean = max(target_vals(:)) / (mean(target_vals(:)) + eps);
quality_score = pcc + energy_efficiency + p10_over_p50 - target_cv - 0.10 * target_peak_over_mean;
scores = [pcc, nmse, energy_efficiency, target_cv, p10_over_p50, max(pred(:)), target_peak_over_mean, quality_score];
end

function phase_step = board_phase_step(cfg)
k_board = 2 * pi * cfg.f0 / cfg.c_board;
k_water = 2 * pi * cfg.f0 / cfg.c_water;
phase_step = abs(k_water - k_board) * cfg.dz;
end

function phase_wrapped = wrap_phase_local(phase_in)
phase_wrapped = mod(phase_in, 2 * pi);
end

function cases = append_case(cases, case_now)
if isempty(cases)
    cases = case_now;
else
    cases(end + 1) = case_now;
end
end

function p_complex_vec = demodulate_kwave_pressure(p_time, t_record, f0)
demod = exp(-1i * 2 * pi * f0 * reshape(t_record, [], 1));
p_complex_vec = (2 / numel(t_record)) * (p_time * demod);
end

function medium_cpu = cast_medium_cpu(medium)
medium_cpu = medium;
medium_cpu.sound_speed = double(medium.sound_speed);
medium_cpu.density = double(medium.density);
if isfield(medium_cpu, 'alpha_coeff')
    medium_cpu.alpha_coeff = double(medium.alpha_coeff);
end
end

function source_cpu = cast_source_cpu(source)
source_cpu = source;
source_cpu.p_mask = double(source.p_mask);
source_cpu.p = double(source.p);
end

function sensor_cpu = cast_sensor_cpu(sensor)
sensor_cpu = sensor;
sensor_cpu.mask = logical(sensor.mask);
end

function Nz = next_fast_grid_size(Nz_required)
preferred = [64, 72, 80, 90, 96, 100, 108, 120, 128, 144, 150, 160, 180, 192, 200, 216, 225, 240, 256, 270, 288, 300, 320, 360, 384, 400, 432, 480, 512];
candidate = preferred(find(preferred >= Nz_required, 1));
if ~isempty(candidate)
    Nz = candidate;
    return;
end
Nz = Nz_required;
while largest_prime_factor(Nz) > 7
    Nz = Nz + 1;
end
end

function value = largest_prime_factor(n)
factors_n = factor(double(n));
value = max(factors_n);
end

function offsets_m = parse_mm_offsets(text_value)
parts = regexp(strtrim(text_value), ',', 'split');
offsets_mm = zeros(1, numel(parts));
for idx = 1:numel(parts)
    offsets_mm(idx) = str2double(strtrim(parts{idx}));
end
if any(~isfinite(offsets_mm))
    error('Invalid HDSP_BOARD_COMPARE_SCAN_OFFSETS_MM: %s', text_value);
end
offsets_m = offsets_mm * 1e-3;
end

function value = env_number(name, default_value)
text_value = getenv(name);
if isempty(text_value)
    value = default_value;
    return;
end
value = str2double(text_value);
if ~isfinite(value)
    error('Environment variable %s must be numeric, got: %s', name, text_value);
end
end

function value = env_flag(name, default_value)
text_value = getenv(name);
if isempty(text_value)
    value = default_value;
    return;
end
value = any(strcmpi(text_value, {'1', 'true', 'yes', 'on'}));
end

function value = getenv_default(name, default_value)
value = getenv(name);
if isempty(value)
    value = default_value;
end
end

function git_commit_short = get_git_commit_short(repo_root)
[status, hash_text] = system(sprintf('git -C "%s" rev-parse --short HEAD', repo_root));
if status ~= 0
    git_commit_short = 'nogit';
    return;
end
git_commit_short = regexprep(strtrim(hash_text), '[^A-Za-z0-9._-]', '_');
if isempty(git_commit_short)
    git_commit_short = 'nogit';
end
end
