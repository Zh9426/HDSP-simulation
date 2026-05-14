clear; close all; clc;

cfg = initial_phase_config();
rng(cfg.rng_seed);
if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end
if ~exist(cfg.transport_dir, 'dir')
    mkdir(cfg.transport_dir);
end

fprintf('==================================================\n');
fprintf('Initial phase study: Board-constrained IASA optimization\n');
fprintf('No curing module. k-Wave evaluates pressure amplitude only.\n');
fprintf('Grid: %d x %d | dx %.4f mm | target z %.2f mm\n', ...
    cfg.Nx, cfg.Ny, cfg.dx * 1e3, cfg.z_target_dist * 1e3);
fprintf('==================================================\n');

target = build_a_phase_target(cfg);
propagator = make_asm_propagator(cfg);

iasa_options = struct();
iasa_options.anchor_eta = cfg.iasa_anchor_eta;
iasa_options.use_dither = true;

pure_seed = zeros(cfg.Nx, cfg.Ny);
pure_seed(target.source_mask) = 2 * pi * rand(nnz(target.source_mask), 1);
pure_iasa_options = iasa_options;
pure_iasa_options.phase_bias_seed = 0;
pure_board_iasa = run_board_constrained_iasa_phase_optimizer( ...
    pure_seed, target.amp, target.source_mask, propagator, cfg, 'Pure Board IASA', pure_iasa_options);

phase_cases = struct([]);
phase_cases(1).label = 'Pure Board IASA';
phase_cases(1).phase = pure_board_iasa.phase;
phase_cases(1).asm_amp = pure_board_iasa.asm_amp;
phase_cases(1).asm_amp_norm = pure_board_iasa.asm_amp_norm;
phase_cases(1).history = pure_board_iasa.history;
phase_cases(1).layer_map = pure_board_iasa.layer_map;
phase_cases(1).phase_step = pure_board_iasa.phase_step;
phase_cases(1).phase_bias = pure_board_iasa.phase_bias;
phase_cases(1).optimizer_metrics = pure_board_iasa.optimizer_metrics;

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

save(fullfile(cfg.output_dir, 'initial_phase_pressure_results.mat'), 'results', '-v7.3');
plot_phase_pressure_comparison(results, fullfile(cfg.output_dir, 'initial_phase_pressure_overview.png'));
summary_report = write_phase_pressure_summary(results, fullfile(cfg.output_dir, 'summary.txt'), fullfile(cfg.output_dir, 'summary.json'));

fprintf('\n==================================================\n');
for idx = 1:numel(phase_cases)
    m = phase_cases(idx).kwave.metrics;
    fprintf('%-14s | best z offset %+5.2f mm | target mean %.3g Pa | peak/mean %.2f | CV %.3f | EE %.2f%%\n', ...
        phase_cases(idx).label, phase_cases(idx).kwave.best_z_offset_m * 1e3, ...
        m.mean_target_pressure_pa, m.target_peak_over_mean, m.target_uniformity_cv, m.energy_efficiency * 100);
end
if isfield(summary_report, 'comparison')
    c = summary_report.comparison;
    fprintf('History rank    | %d / %d by %s\n', c.rank, c.num_compared_runs, c.ranking_metric);
    fprintf('History status  | %s\n', c.status);
    if isfield(c, 'prior_best') && isfield(c.prior_best, 'commit')
        fprintf('Prior best      | %s | score %.4f\n', c.prior_best.commit, c.prior_best.score);
        fprintf('Delta vs best   | score %+.4f | PCC %+.4f | EE %+.2f%% | CV %+.4f\n', ...
            c.delta_vs_prior_best.score, c.delta_vs_prior_best.pcc, ...
            c.delta_vs_prior_best.energy_efficiency * 100, c.delta_vs_prior_best.target_uniformity_cv);
    end
    fprintf('Next direction  | %s\n', c.recommendation);
end
fprintf('Outputs written under ignored directory: %s\n', cfg.output_dir);
fprintf('==================================================\n');

% The Python transport helpers are kept for quick re-enabling of comparison
% cases, but the current study mode intentionally runs BIASA only.
function export_pann_transport_input(cfg, target)
imag_target = target.amp;
imag_target_design = target.amp;
source_mask = target.source_mask;
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
save(cfg.python_input_mat, 'imag_target', 'imag_target_design', 'source_mask', 'Nx', 'Ny', 'Lx', ...
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

function value = read_optional_scalar(data, field_name, default_value)
if isfield(data, field_name) && ~isempty(data.(field_name))
    value = double(data.(field_name)(1));
else
    value = default_value;
end
end
