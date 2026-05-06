clear; close all; clc;

cfg = initial_phase_config();
rng(cfg.rng_seed);
if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end

fprintf('==================================================\n');
fprintf('Initial phase study: Python vs Python+IASA vs Pure IASA\n');
fprintf('No curing module. k-Wave evaluates pressure amplitude only.\n');
fprintf('Grid: %d x %d | dx %.4f mm | target z %.2f mm\n', ...
    cfg.Nx, cfg.Ny, cfg.dx * 1e3, cfg.z_target_dist * 1e3);
fprintf('==================================================\n');

target = build_a_phase_target(cfg);
save(cfg.python_input_mat, 'target', 'cfg', '-v7');
wait_for_python_phase_output(cfg);

python_data = load(cfg.python_output_mat, 'phase_python', 'python_loss_history', 'python_asm_amp');
phase_python = wrap_phase(python_data.phase_python);
phase_python(~target.source_mask) = 0;

propagator = make_asm_propagator(cfg);
python_focus = compute_asm_focus_field(phase_python, target.source_mask, propagator);

python_iasa = run_iasa_phase_optimizer( ...
    phase_python, target.amp, target.source_mask, propagator, cfg, 'Python + IASA');

pure_iasa_seed = zeros(cfg.Nx, cfg.Ny);
pure_iasa_seed(target.source_mask) = 2 * pi * rand(nnz(target.source_mask), 1);
pure_iasa = run_iasa_phase_optimizer( ...
    pure_iasa_seed, target.amp, target.source_mask, propagator, cfg, 'Pure IASA');

phase_cases = struct([]);
phase_cases(1).label = 'Pure Python';
phase_cases(1).phase = phase_python;
phase_cases(1).asm_amp = python_focus.amp;
phase_cases(1).asm_amp_norm = python_focus.amp_norm;
phase_cases(1).history = python_data.python_loss_history;

phase_cases(2).label = 'Python + IASA';
phase_cases(2).phase = python_iasa.phase;
phase_cases(2).asm_amp = python_iasa.asm_amp;
phase_cases(2).asm_amp_norm = python_iasa.asm_amp_norm;
phase_cases(2).history = python_iasa.history;

phase_cases(3).label = 'Pure IASA';
phase_cases(3).phase = pure_iasa.phase;
phase_cases(3).asm_amp = pure_iasa.asm_amp;
phase_cases(3).asm_amp_norm = pure_iasa.asm_amp_norm;
phase_cases(3).history = pure_iasa.history;

for idx = 1:numel(phase_cases)
    phase_cases(idx).asm_metrics = calculate_pressure_metrics( ...
        phase_cases(idx).asm_amp, target.amp, target.mask, target.x, target.y);
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
write_phase_pressure_summary(results, fullfile(cfg.output_dir, 'summary.txt'), fullfile(cfg.output_dir, 'summary.json'));

fprintf('\n==================================================\n');
for idx = 1:numel(phase_cases)
    m = phase_cases(idx).kwave.metrics;
    fprintf('%-14s | best z offset %+5.2f mm | target peak %.3g Pa | PCC %.4f | EE %.2f%% | contrast %.2f\n', ...
        phase_cases(idx).label, phase_cases(idx).kwave.best_z_offset_m * 1e3, ...
        m.peak_target_pressure_pa, m.pcc, m.energy_efficiency * 100, m.focus_contrast);
end
fprintf('Outputs written under ignored directory: %s\n', cfg.output_dir);
fprintf('==================================================\n');

function wait_for_python_phase_output(cfg)
command = sprintf('"%s" "%s" --input "%s" --output "%s" --epochs %d --lr %.8g', ...
    cfg.python_executable, cfg.python_script, cfg.python_input_mat, ...
    cfg.python_output_mat, cfg.python_epochs, cfg.python_learning_rate);
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
