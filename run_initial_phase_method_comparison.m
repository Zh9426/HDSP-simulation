clear; close all; clc;

cfg = initial_phase_config();
cfg.iasa_epochs = 600;
cfg.output_root_dir = fullfile(cfg.repo_root, 'initial_phase_method_outputs');
cfg.output_dir = fullfile(cfg.output_root_dir, cfg.git_commit_short);

rng(cfg.rng_seed);
if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end
if ~exist(cfg.transport_dir, 'dir')
    mkdir(cfg.transport_dir);
end

fprintf('==================================================\n');
fprintf('Initial phase method comparison: GS / WIASA / BIASA / Python hybrids\n');
fprintf('IASA epochs: %d. No curing module. k-Wave evaluates pressure amplitude only.\n', cfg.iasa_epochs);
fprintf('Grid: %d x %d | dx %.4f mm | target z %.2f mm\n', ...
    cfg.Nx, cfg.Ny, cfg.dx * 1e3, cfg.z_target_dist * 1e3);
fprintf('Outputs: %s\n', cfg.output_dir);
fprintf('==================================================\n');

target = build_a_phase_target(cfg);
propagator = make_asm_propagator(cfg);

export_pann_transport_input(cfg, target);
wait_for_python_phase_output(cfg);
python_phase_case = import_python_phase_case(cfg, target, propagator);

pure_seed = zeros(cfg.Nx, cfg.Ny);
pure_seed(target.source_mask) = 2 * pi * rand(nnz(target.source_mask), 1);

iasa_options = struct();
iasa_options.anchor_eta = cfg.iasa_anchor_eta;
iasa_options.use_dither = true;
iasa_options.phase_bias_seed = 0;

phase_cases = struct([]);
phase_cases = append_case(phase_cases, standardize_phase_case( ...
    run_continuous_iasa_phase_optimizer(pure_seed, target.amp, target.source_mask, propagator, cfg, 'GS', 'gs')));
phase_cases = append_case(phase_cases, standardize_phase_case( ...
    run_continuous_iasa_phase_optimizer(pure_seed, target.amp, target.source_mask, propagator, cfg, 'WIASA', 'wiasa')));
phase_cases = append_case(phase_cases, standardize_phase_case( ...
    run_board_constrained_iasa_phase_optimizer(pure_seed, target.amp, target.source_mask, propagator, cfg, 'BIASA', iasa_options)));
phase_cases = append_case(phase_cases, standardize_phase_case(python_phase_case));

python_biasa_options = iasa_options;
python_biasa_options.phase_bias_seed = read_python_phase_bias(python_phase_case);
phase_cases = append_case(phase_cases, standardize_phase_case( ...
    run_board_constrained_iasa_phase_optimizer(python_phase_case.phase, target.amp, target.source_mask, propagator, cfg, 'Python + BIASA', python_biasa_options)));
phase_cases = append_case(phase_cases, standardize_phase_case( ...
    run_continuous_iasa_phase_optimizer(python_phase_case.phase, target.amp, target.source_mask, propagator, cfg, 'Python + WIASA', 'wiasa')));

for idx = 1:numel(phase_cases)
    phase_cases(idx).asm_metrics = calculate_pressure_metrics( ...
        phase_cases(idx).asm_amp, target.amp, target.mask, target.x, target.y);
    phase_cases(idx).phase_metrics = calculate_phase_metrics( ...
        phase_cases(idx).phase, target.source_mask, target.amp, phase_cases(idx).asm_amp, phase_cases(idx).label);
end

for idx = 1:numel(phase_cases)
    phase_cases(idx).kwave = run_kwave_pressure_scan( ...
        phase_cases(idx).phase, target.source_mask, target, cfg, phase_cases(idx).label);
end

results = struct();
results.cfg = cfg;
results.phase_cases = phase_cases;
results.target = target;
results.created_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

save(fullfile(cfg.output_dir, 'initial_phase_method_comparison_results.mat'), 'results', '-v7.3');
plot_phase_method_comparison(results, fullfile(cfg.output_dir, 'initial_phase_method_comparison_overview.png'));
summary_report = write_phase_method_comparison_summary(results, ...
    fullfile(cfg.output_dir, 'summary.txt'), ...
    fullfile(cfg.output_dir, 'summary.json'), ...
    fullfile(cfg.output_dir, 'method_comparison.csv'));

fprintf('\n==================================================\n');
fprintf('Method comparison ranking by k-Wave target_pressure_quality_score\n');
for idx = 1:numel(summary_report.ranking)
    c = summary_report.ranking(idx);
    fprintf('%d. %-16s | score %.4f | CV %.3f | P10/P50 %.3f | peak/mean %.2f | darkP99/P50 %.3f | EE %.2f%%\n', ...
        idx, c.label, c.target_pressure_quality_score, c.target_uniformity_cv, ...
        c.target_p10_over_p50, c.target_peak_over_mean, ...
        c.dark_p99_over_target_p50, c.energy_efficiency * 100);
end
fprintf('Outputs written under ignored directory: %s\n', cfg.output_dir);
fprintf('==================================================\n');

function export_pann_transport_input(cfg, target)
imag_target = target.amp;
imag_target_design = target.amp;
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
thermal_sigma_px = cfg.target_blur_sigma_px;
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

if exist(cfg.python_output_mat, 'file')
    delete(cfg.python_output_mat);
end
save(cfg.python_input_mat, 'imag_target', 'imag_target_design', 'Nx', 'Ny', 'Lx', ...
    'lambda_water', 'z_target_dist', 'dx', 'dz', 'f0', 'c_water', ...
    'c_board', 'thermal_sigma_px', 'min_base_layers', ...
    'target_threshold_norm', 'low_quantile_goal', ...
    'target_mean_amp_goal_ratio', 'python_z_constraint_offsets_m', ...
    'branch_output_dir', 'python_epochs', 'python_learning_rate', ...
    'python_min_epochs', 'python_early_stop_patience', 'python_rng_seed', ...
    'python_lr_restart_cycle', 'python_lr_restart_decay', 'python_lr_min_ratio');
end

function wait_for_python_phase_output(cfg)
command = sprintf('"%s" "%s"', cfg.python_executable, cfg.python_script);
fprintf('\n==================================================\n');
fprintf('Python optimizer input written to:\n%s\n\n', cfg.python_input_mat);
fprintf('Run this command manually in PowerShell, then return to MATLAB and press any key:\n%s\n', command);
fprintf('Expected Python output:\n%s\n', cfg.python_output_mat);
fprintf('==================================================\n\n');
pause;
if ~exist(cfg.python_output_mat, 'file')
    error('Python optimizer output not found: %s', cfg.python_output_mat);
end
end

function result = import_python_phase_case(cfg, target, propagator)
data = load(cfg.python_output_mat);
if ~isfield(data, 'optimal_initial_phase')
    error('Python output has no optimal_initial_phase: %s', cfg.python_output_mat);
end
phase = double(data.optimal_initial_phase);
if ~isequal(size(phase), [cfg.Nx, cfg.Ny])
    error('Python phase size mismatch. Expected %d x %d, got %d x %d.', cfg.Nx, cfg.Ny, size(phase, 1), size(phase, 2));
end
phase = wrap_phase(phase);
phase(~target.source_mask) = 0;
focus = compute_asm_focus_field(phase, target.source_mask, propagator);

result = struct();
result.label = 'Python';
result.phase = phase;
result.asm_amp = focus.amp;
result.asm_amp_norm = focus.amp_norm;
result.history = [];
result.layer_map = read_optional_field(data, 'optimal_layer_map', []);
result.phase_step = read_optional_scalar(data, 'phase_step', NaN);
result.phase_bias = read_optional_scalar(data, 'optimal_phase_bias', 0);
result.optimizer_metrics = struct( ...
    'optimizer_mode', 'python', ...
    'board_projection', true, ...
    'python_history_rows', read_python_history_rows(data), ...
    'phase_bias', result.phase_bias, ...
    'phase_step', result.phase_step);
end

function phase_bias = read_python_phase_bias(python_case)
phase_bias = 0;
if isfield(python_case, 'phase_bias') && ~isempty(python_case.phase_bias) && isfinite(python_case.phase_bias)
    phase_bias = python_case.phase_bias;
end
end

function rows = read_python_history_rows(data)
if isfield(data, 'python_loss_history') && ~isempty(data.python_loss_history)
    rows = size(data.python_loss_history, 1);
else
    rows = 0;
end
end

function value = read_optional_scalar(data, field_name, default_value)
if isfield(data, field_name) && ~isempty(data.(field_name))
    value = double(data.(field_name)(1));
else
    value = default_value;
end
end

function value = read_optional_field(data, field_name, default_value)
if isfield(data, field_name) && ~isempty(data.(field_name))
    value = data.(field_name);
else
    value = default_value;
end
end

function cases = append_case(cases, case_now)
if isempty(cases)
    cases = case_now;
else
    cases(end + 1) = case_now;
end
end

function case_out = standardize_phase_case(case_in)
case_out = struct();
case_out.label = case_in.label;
case_out.phase = case_in.phase;
case_out.asm_amp = case_in.asm_amp;
case_out.asm_amp_norm = case_in.asm_amp_norm;
case_out.history = read_result_field(case_in, 'history', []);
case_out.layer_map = read_result_field(case_in, 'layer_map', []);
case_out.phase_step = read_result_field(case_in, 'phase_step', NaN);
case_out.phase_bias = read_result_field(case_in, 'phase_bias', NaN);
case_out.optimizer_metrics = read_result_field(case_in, 'optimizer_metrics', struct());
case_out.asm_metrics = struct();
case_out.phase_metrics = struct();
case_out.kwave = struct();
end

function value = read_result_field(data, field_name, default_value)
if isfield(data, field_name) && ~isempty(data.(field_name))
    value = data.(field_name);
else
    value = default_value;
end
end
