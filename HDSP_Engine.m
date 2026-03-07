function results = HDSP_Engine(params)
% HDSP_Engine: 核心声学与热力学仿真计算引擎
% 输入: params 结构体 (包含来自 App UI 的参数)
% 输出: results 结构体 (包含用于 App 绘图的所有 2D/3D 矩阵数据)

    % 1. 强制清空 GPU 底层，确保满血运行 (可选，防止多次运行显存爆炸)
    reset(gpuDevice); 

    %% === [1. 参数解析 (从 App 传入)] ===
    Nx = params.Nx; % 推荐 256 或 384
    f0 = params.f0 * 1e6; % 将 MHz 转换为 Hz
    target_median_pressure = params.pressure * 1e6; % MPa -> Pa
    cavitation_limit = params.limit * 1e6; % MPa -> Pa
    exposure_time = params.time;
    Thermal_Curing_Threshold = params.threshold;

    %% === [2. 物理网格构建] ===
    Lx = 40e-3; Ny = Nx; Ly = Lx;
    z_target_dist = 20e-3; 
    c_water = 1480; c_board = 2430; 
    density_water = 997; density_board = 1100; 
    lambda_water = c_water / f0;
    
    dx = Lx / Nx; dy = dx; dz = dx; 
    Lz_needed = 30e-3; 
    Nz_min = ceil(Lz_needed / dz);
    optimal_sizes = [128, 192, 216, 256, 300, 384, 512];
    Nz = optimal_sizes(find(optimal_sizes >= Nz_min, 1));
    Lz = Nz * dz;
    x = (-Nx/2 : Nx/2-1) * dx;

    %% === [3. 目标定义与软边界处理] ===
    imag_target = zeros(Nx, Ny);
    h_A = 160; w_base = 100; thickness = 22; bar_pos = 50; bar_width = 20;
    cx = round(Nx/2); cy = round(Ny/2);
    x_top = cx - h_A/2; x_bottom = cx + h_A/2; slope = h_A / (w_base/2);
    [Y_grid, X_grid] = meshgrid(1:Ny, 1:Nx);
    dx_outer = X_grid - x_top; dy_abs = abs(Y_grid - cy);
    width_at_x = dx_outer / slope;
    mask_outer = (dx_outer >= 0) & (dx_outer <= h_A) & (dy_abs <= width_at_x);
    x_top_inner = x_top + thickness * 1.8; 
    dx_inner = X_grid - x_top_inner;
    width_inner_at_x = dx_inner / slope;
    mask_inner_cone = (dx_inner >= 0) & (dy_abs <= width_inner_at_x); 
    x_bar_start = x_bottom - bar_pos - bar_width/2;
    x_bar_end   = x_bottom - bar_pos + bar_width/2;
    mask_bar = (X_grid >= x_bar_start) & (X_grid <= x_bar_end);
    imag_target = mask_outer & (~mask_inner_cone | mask_bar);
    imag_target = double(imag_target > 0.5);
    
    % 高斯软边界
    smooth_sigma = 1.5; 
    imag_target = imgaussfilt(imag_target, smooth_sigma);
    imag_target = imag_target / max(imag_target(:));

   %% === [4. W-IASA 全息迭代] ===
    pad_factor = 2; Nx_pad = Nx * pad_factor; Ny_pad = Ny * pad_factor;
    Lx_pad = Lx * pad_factor; dk_pad = 2 * pi / Lx_pad;
    kx_pad = (-Nx_pad/2 : Nx_pad/2-1) * dk_pad;
    [Kx_pad, Ky_pad] = meshgrid(kx_pad, kx_pad);
    k_water = 2 * pi / lambda_water;
    Kz_sq = k_water^2 - Kx_pad.^2 - Ky_pad.^2; Kz_sq(Kz_sq < 0) = 0; 
    H_forward = exp(1i * sqrt(Kz_sq) * z_target_dist); 
    H_backward = exp(-1i * sqrt(Kz_sq) * z_target_dist); 
    
    rng(9426);
    board_phase_pad = zeros(Nx_pad, Ny_pad);
    
    % [修复 1: 恢复低频相位起手式，消灭初始相位奇点]
    raw_rand_phase = rand(Nx, Nx) * 2 * pi;
    smooth_initial_phase = imgaussfilt(raw_rand_phase, 8); 
    board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = exp(1i * smooth_initial_phase);

    target_pad = zeros(Nx_pad, Ny_pad);
    target_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = imag_target;
    weight_pad = target_pad * 1.5; 
    mask_roi = (target_pad > 0.5); mask_dark = (target_pad < 0.5);    
    
    epoch = 150; 
    for i = 1:epoch
        U_source = zeros(Nx_pad, Ny_pad);
        center_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));
        U_source(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = 1.0 .* exp(1i * center_phase);
        
        A_source = fftshift(fft2(ifftshift(U_source)));
        A_target = A_source .* H_forward;
        U_target = fftshift(ifft2(ifftshift(A_target)));
        
        rec_amp = abs(U_target);
        
        % [修复 2: 恢复迭代内平滑约束，给算法戴上“近视眼镜”]
        rec_amp_blurred = imgaussfilt(rec_amp, 1.2); 
        
        peak_val = max(rec_amp_blurred(mask_roi)); 
        if peak_val == 0, peak_val = max(rec_amp_blurred(:)); end
        rec_amp_norm = rec_amp_blurred / peak_val;
        
        if i > 5
            beta = 0.8; 
            correction = (target_pad(mask_roi) ./ (rec_amp_norm(mask_roi) + 1e-6)) .^ beta;
            weight_pad(mask_roi) = weight_pad(mask_roi) .* correction;
            weight_pad(weight_pad > 10) = 10;
            weight_pad(mask_dark) = 0;
        end
        U_target_constrained = weight_pad .* exp(1i * angle(U_target));
        A_target_cons = fftshift(fft2(ifftshift(U_target_constrained)));
        A_source_cons = A_target_cons .* H_backward;
        U_source_new = fftshift(ifft2(ifftshift(A_source_cons)));
        board_phase_pad = U_source_new;
    end
    holo_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));
    final_weight = weight_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny);

    %% === [5. 物理体素化] ===
    phase_wrapped = mod(holo_phase, 2*pi); 
    k_board_val = 2 * pi * f0 / c_board; k_water_val = 2 * pi * f0 / c_water;
    k_diff = abs(k_water_val - k_board_val); 
    thickness_ideal = phase_wrapped / k_diff;
    thickness_map = imgaussfilt(thickness_ideal, 0.2) + 2 * dz; 
    net_num_board = round(thickness_map / dz);
    actual_thickness = net_num_board * dz;
    
    actual_phase_imparted = mod(actual_thickness * k_diff, 2*pi);
    complex_diff_voxel = exp(1i * actual_phase_imparted) ./ exp(1i * phase_wrapped);
    global_offset_voxel = angle(mean(complex_diff_voxel(:))); 
    phase_aligned_voxel = angle(exp(1i * (actual_phase_imparted - global_offset_voxel)));
    phase_error_voxel = abs(angle(exp(1i * (phase_aligned_voxel - phase_wrapped))));
    mean_phase_error = mean(phase_error_voxel(:));

    %% === [6. k-Wave 环境与声波仿真] ===
    kgrid = kWaveGrid(Nx, dx, Ny, dy, Nz, dz);
    medium.sound_speed = c_water * ones(Nx, Ny, Nz);
    rho_match = (c_water * density_water) / c_board;
    medium.density = density_water * ones(Nx, Ny, Nz);
    medium.alpha_coeff = 0.002 * ones(Nx, Ny, Nz); 
    medium.alpha_power = 1.5;

    pml_size = 10; source_z_idx = pml_size + 5; z_board_stat_idx = source_z_idx + 2;
    for i = 1:Nx
        for j = 1:Ny
            n_layers = net_num_board(i, j);
            if n_layers > 0
                z_start = z_board_stat_idx; z_end = z_board_stat_idx + n_layers - 1;
                medium.sound_speed(i, j, z_start:z_end) = c_board;
                medium.density(i, j, z_start:z_end) = rho_match; 
            end
        end
    end
    thickest = max(net_num_board(:)) * dz;

    cfl = 0.3; t_end = (Lz * 1.5) / c_water; 
    kgrid.makeTime(medium.sound_speed, cfl, t_end); 
    source.p_mask = zeros(Nx, Ny, Nz); source.p_mask(:, :, source_z_idx) = 1; 
    ramp_pts = round(2 / f0 / kgrid.dt); 
    window = [linspace(0,1,ramp_pts), ones(1, kgrid.Nt-ramp_pts)];
    source.p = sin(2 * pi * f0 * kgrid.t_array) .* window;
    source.p_mode = 'dirichlet';

    sensor.mask = zeros(Nx, Ny, Nz);
    z_board_exit_idx = z_board_stat_idx + round(thickest/dz);
    target_plane_idx = z_board_exit_idx + round(z_target_dist / dz);
    scan_range_idx = round(3e-3 / dz); 
    z_scan_start = target_plane_idx - scan_range_idx;
    z_scan_end = min(target_plane_idx + scan_range_idx, Nz - pml_size);
    sensor.mask(:, :, z_scan_start:z_scan_end) = 1;
    sensor.record = {'p'}; 
    sensor.record_start_index = kgrid.Nt - round(3/f0/kgrid.dt);

    input_args = {'PMLInside', true, 'PMLSize', 10, 'PlotPML', false, 'PlotSim', false, 'DataCast', 'gpuArray-single'};
    try
        sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
    catch
        input_args = input_args(1:end-2);
        sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
    end

    %% === [7. Z-Scan 寻焦评估] ===
    p_raw = gather(sensor_data.p); 
    [~, Nt_rec] = size(p_raw);
    p_fft = fft(p_raw, [], 2);
    [~, f_idx] = min(abs( (0:Nt_rec-1)/Nt_rec/kgrid.dt - f0 ));
    p_complex = p_fft(:, f_idx);
    
    p_field_3d = zeros(Nx, Ny, Nz);
    p_field_3d(find(sensor.mask)) = p_complex;
    scan_vol = abs(p_field_3d(:, :, z_scan_start:z_scan_end));
    num_slices = size(scan_vol, 3);
    
    R = double(imag_target); R = (R - min(R(:))) / (max(R(:)) - min(R(:))); R_mean = mean(R(:));
    best_corr = -1; best_slice_idx = 1;
    metrics_z = zeros(num_slices, 1); metrics_corr = zeros(num_slices, 1);
    
    for k = 1:num_slices
        A = scan_vol(:, :, k); A = (A - min(A(:))) / (max(A(:)) - min(A(:))); A_mean = mean(A(:));
        val_corr = sum(sum((R - R_mean) .* (A - A_mean))) / sqrt(sum(sum((R - R_mean).^2)) * sum(sum((A - A_mean).^2)));
        metrics_z(k) = (z_scan_start + k - 1 - z_board_exit_idx) * dz * 1e3;
        metrics_corr(k) = val_corr;
        if val_corr > best_corr
            best_corr = val_corr; best_slice_idx = k;
        end
    end
    best_idx_global = z_scan_start + best_slice_idx - 1;
    actual_z_dist_mm = (best_idx_global - z_board_exit_idx) * dz * 1e3;

    %% === [8. FDTD 热扩散仿真] ===
    p_3d_abs = abs(p_field_3d); 
    focal_slice_abs = p_3d_abs(:, :, best_idx_global);
    roi_mask = (imag_target > 0.5);
    median_roi_p = median(focal_slice_abs(roi_mask)); 
    
    scale_factor = target_median_pressure / median_roi_p;
    p_3d_scaled = p_3d_abs * scale_factor;
    p_3d_scaled(p_3d_scaled > cavitation_limit) = cavitation_limit; 
    
    rho_resin = 1100; c_resin = 2500; Cp_resin = 1500; k_resin = 0.2; 
    rho_water = 997; c_water = 1480; Cp_water = 4180; k_water = 0.6; 
    alpha_np_resin = (1.5 / 8.686) * 100 * (f0/1e6)^1.5; alpha_np_water = 0.02; 
    resin_z_start = z_board_exit_idx + 1;
    
    Q_heat_3d = zeros(Nx, Ny, Nz, 'single');
    I_3d_resin = single((p_3d_scaled(:, :, resin_z_start:end).^2) ./ (2 * rho_resin * c_resin));
    Q_heat_3d(:, :, resin_z_start:end) = 2 * alpha_np_resin * I_3d_resin;
    I_3d_water = single((p_3d_scaled(:, :, 1:resin_z_start-1).^2) ./ (2 * rho_water * c_water));
    Q_heat_3d(:, :, 1:resin_z_start-1) = 2 * alpha_np_water * I_3d_water;
    
    diffusivity_3d = zeros(Nx, Ny, Nz, 'single');
    diffusivity_3d(:, :, resin_z_start:end) = k_resin / (rho_resin * Cp_resin);
    diffusivity_3d(:, :, 1:resin_z_start-1) = k_water / (rho_water * Cp_water);
    rho_Cp_3d = zeros(Nx, Ny, Nz, 'single');
    rho_Cp_3d(:, :, resin_z_start:end) = rho_resin * Cp_resin;
    rho_Cp_3d(:, :, 1:resin_z_start-1) = rho_water * Cp_water;
    dT_source_3d = Q_heat_3d ./ rho_Cp_3d;
    
    z_crop_radius = round(1.5e-3 / dz); 
    z_crop_start = max(1, best_idx_global - z_crop_radius);
    z_crop_end = min(Nz, best_idx_global + z_crop_radius);
    best_idx_crop = best_idx_global - z_crop_start + 1;
    
    try
        T_3d_gpu = gpuArray(60 * ones(Nx, Ny, z_crop_end - z_crop_start + 1, 'single'));
        diffusivity_gpu = gpuArray(diffusivity_3d(:, :, z_crop_start:z_crop_end));
        dT_source_gpu = gpuArray(dT_source_3d(:, :, z_crop_start:z_crop_end));
    catch
        T_3d_gpu = 60 * ones(Nx, Ny, z_crop_end - z_crop_start + 1, 'single');
        diffusivity_gpu = diffusivity_3d(:, :, z_crop_start:z_crop_end);
        dT_source_gpu = dT_source_3d(:, :, z_crop_start:z_crop_end);
    end
    
    max_diffusivity = max(k_resin/(rho_resin*Cp_resin), k_water/(rho_water*Cp_water));
    dt_th_max = (dx^2) / (6 * max_diffusivity); dt_th = dt_th_max * 0.9; 
    Nt_th = round(exposure_time / dt_th);
    T_max_history = zeros(Nt_th, 1);
    
    for step = 1:Nt_th
        laplacian_T = 6 * del2(T_3d_gpu, dx);
        T_3d_gpu = T_3d_gpu + dt_th * (diffusivity_gpu .* laplacian_T + dT_source_gpu);
        T_max_history(step) = gather(max(max(T_3d_gpu(:, :, best_idx_crop))));
    end
    
    T_focal_2d = gather(double(T_3d_gpu(:, :, best_idx_crop)));
    T_max_real = T_max_history(end);
    Q_focal_2d = gather(double(dT_source_gpu(:, :, best_idx_crop) * rho_resin * Cp_resin));

    %% === [9. 数据打包输出给 App] ===
    cured_mask_2d = T_focal_2d > Thermal_Curing_Threshold;
    R_binary = imag_target > 0.5;
    IoU = sum(sum(R_binary & cured_mask_2d)) / sum(sum(R_binary | cured_mask_2d));
    cured_coverage = (sum(cured_mask_2d(:)) / sum(R_binary(:))) * 100;
    if cured_coverage > 100, cured_coverage = 100; end

    % 填装所有需要展示的数据
    results.x = x * 1e3; % mm
    results.y = x * 1e3; % mm
    results.imag_target = imag_target;
    results.phase_wrapped = phase_wrapped;
    results.actual_thickness = actual_thickness * 1e3; % mm
    results.phase_aligned_voxel = phase_aligned_voxel;
    results.mean_phase_error = mean_phase_error * 180 / pi;
    results.final_weight = final_weight;
    results.Q_focal_2d = Q_focal_2d / 1e6;
    results.p_focal_scaled = gather(p_3d_scaled(:, :, best_idx_global)) / 1e6; % MPa
    results.cured_mask_2d = cured_mask_2d;
    results.T_focal_2d = T_focal_2d;
    results.IoU = IoU;
    results.cured_coverage = cured_coverage;
    results.metrics_z = metrics_z;
    results.metrics_corr = metrics_corr;
    results.actual_z_dist_mm = actual_z_dist_mm;
    results.best_corr = best_corr;
    results.T_max_real = T_max_real;
    results.t_axis = (1:Nt_th) * dt_th;
    results.T_max_history = T_max_history;

end