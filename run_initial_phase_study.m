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
fprintf('Initial phase study: Pure Python phase optimization\n');
fprintf('No curing module. k-Wave evaluates pressure amplitude only.\n');
fprintf('Grid: %d x %d | dx %.4f mm | target z %.2f mm\n', ...
    cfg.Nx, cfg.Ny, cfg.dx * 1e3, cfg.z_target_dist * 1e3);
fprintf('==================================================\n');

target = build_a_phase_target(cfg);
export_pann_transport_input(cfg, target);
wait_for_python_phase_output(cfg);

python_data = load(cfg.python_output_mat, 'optimal_initial_phase', 'optimal_phase_bias', ...
    'optimal_layer_map', 'python_loss_history', 'python_metrics', 'python_asm_amp_norm');
phase_python = wrap_phase(python_data.optimal_initial_phase);
phase_python(~target.source_mask) = 0;

propagator = make_asm_propagator(cfg);
python_focus = compute_asm_focus_field(phase_python, target.source_mask, propagator);

phase_cases = struct([]);
phase_cases(1).label = 'Pure Python';
phase_cases(1).phase = phase_python;
phase_cases(1).asm_amp = python_focus.amp;
phase_cases(1).asm_amp_norm = python_focus.amp_norm;
phase_cases(1).history = [];
if isfield(python_data, 'python_loss_history')
    phase_cases(1).history = python_data.python_loss_history;
end
if isfield(python_data, 'python_metrics')
    phase_cases(1).optimizer_metrics = python_data.python_metrics;
end

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
save(cfg.python_input_mat, 'imag_target', 'imag_target_design', 'Nx', 'Ny', 'Lx', ...
    'lambda_water', 'z_target_dist', 'dx', 'dz', 'f0', 'c_water', ...
    'c_board', 'thermal_sigma_px', 'min_base_layers', ...
    'target_threshold_norm', 'low_quantile_goal', ...
    'target_mean_amp_goal_ratio', 'python_z_constraint_offsets_m', ...
    'branch_output_dir');
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
