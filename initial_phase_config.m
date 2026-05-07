function cfg = initial_phase_config()
%INITIAL_PHASE_CONFIG Central parameters for initial-phase comparison runs.
cfg.Nx = 512;
cfg.Ny = 512;
cfg.Lx = 65e-3;
cfg.Ly = 65e-3;
cfg.dx = cfg.Lx / cfg.Nx;
cfg.dy = cfg.Ly / cfg.Ny;
cfg.dz = cfg.dx;

cfg.f0 = 4.5e6;
cfg.c_water = 1480;
cfg.c_board = 2430;
cfg.density_water = 997;
cfg.lambda_water = cfg.c_water / cfg.f0;
cfg.z_target_dist = 16e-3;
cfg.pad_factor = 2;
cfg.rng_seed = 9426;

cfg.source_radius = 32e-3;
cfg.source_pressure_pa = 1.0e5;
cfg.focus_scan_offsets_m = (-1.0e-3:0.5e-3:1.0e-3);
cfg.gpu_cooldown_seconds = 30;

cfg.a_height = 20e-3;
cfg.a_base_width = 15e-3;
cfg.a_width = 1.4e-3;
cfg.a_bar_width = 8.0e-3;
cfg.a_bar_y = -1.5e-3;
cfg.target_radius = 15e-3;
cfg.target_blur_sigma_px = 0.65;
cfg.target_mask_threshold = 0.45;
cfg.target_threshold_norm = 0.60;
cfg.low_quantile_goal = 0.88;
cfg.target_mean_amp_goal_ratio = 0.12;
cfg.python_z_constraint_offsets_m = 0;
cfg.min_base_layers = 2;

cfg.iasa_epochs = 150;
cfg.iasa_beta = 0.65;
cfg.iasa_dark_weight = 0.02;
cfg.iasa_target_gain_limit = 8.0;

cfg.python_epochs = 10000;
cfg.python_learning_rate = 0.06;
cfg.python_min_epochs = 6500;
cfg.python_early_stop_patience = 4200;
cfg.python_rng_seed = cfg.rng_seed;
cfg.python_lr_restart_cycle = 5000;
cfg.python_lr_restart_decay = 0.82;
cfg.python_lr_min_ratio = 0.05;
cfg.python_executable = 'python';

cfg.git_commit_short = get_git_commit_short();
cfg.output_root_dir = fullfile(pwd, 'initial_phase_outputs');
cfg.output_dir = fullfile(cfg.output_root_dir, cfg.git_commit_short);
cfg.transport_dir = 'C:\Users\Zh89\Desktop\transport';
cfg.python_input_mat = fullfile(cfg.transport_dir, 'target_for_python.mat');
cfg.python_output_mat = fullfile(cfg.transport_dir, 'dl_phase_init.mat');
cfg.python_script = fullfile(pwd, 'PANN_Holography.py');
end

function git_commit_short = get_git_commit_short()
[status, hash_text] = system('git rev-parse --short HEAD');
if status ~= 0
    git_commit_short = 'nogit';
    return;
end
git_commit_short = strtrim(hash_text);
git_commit_short = regexprep(git_commit_short, '[^A-Za-z0-9._-]', '_');
if isempty(git_commit_short)
    git_commit_short = 'nogit';
end
end
