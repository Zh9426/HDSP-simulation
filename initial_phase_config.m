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
cfg.density_water = 997;
cfg.z_target_dist = 16e-3;
cfg.pad_factor = 2;
cfg.rng_seed = 9426;

cfg.source_radius = 32e-3;
cfg.source_pressure_pa = 1.0e5;
cfg.focus_scan_offsets_m = (-1.0e-3:0.5e-3:1.0e-3);

cfg.a_height = 20e-3;
cfg.a_base_width = 15e-3;
cfg.a_width = 1.4e-3;
cfg.a_bar_width = 8.0e-3;
cfg.a_bar_y = -1.5e-3;
cfg.target_radius = 15e-3;
cfg.target_blur_sigma_px = 0.65;
cfg.target_mask_threshold = 0.45;

cfg.iasa_epochs = 150;
cfg.iasa_beta = 0.65;
cfg.iasa_dark_weight = 0.02;
cfg.iasa_target_gain_limit = 8.0;

cfg.python_epochs = 2500;
cfg.python_learning_rate = 0.35;
cfg.python_executable = 'python';

cfg.output_dir = fullfile(pwd, 'initial_phase_outputs');
cfg.python_input_mat = fullfile(cfg.output_dir, 'python_phase_input.mat');
cfg.python_output_mat = fullfile(cfg.output_dir, 'python_phase_output.mat');
cfg.python_script = fullfile(pwd, 'python_initial_phase_optimizer.py');
end
