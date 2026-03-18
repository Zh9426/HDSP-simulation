clear; close all; clc;

reset(gpuDevice); % 强制清空 GPU 显存底层垃圾，确保 k-Wave 每次都能在 15 分钟内跑完！
%% 1. 网格及参数设定 (完全保持原样)
%% 1. 网格及参数设定 (动态 Z 轴优化与各项同性网格)
% --- 你可以在这里切换 Nx = 256, 384, 或 512 来控制分辨率 ---
Nx = 512; 
% -----------------------------------------------------------

Lx = 40e-3;
Ny = Nx; Ly = Lx;
System_Offset = 2.03e-3;
z_target_dist = 20e-3; % 目标距离
f0 = 6.0e6;
c_water = 1480; 
c_board = 2430; 
density_water = 997;
density_board = 1100; 
lambda_water = c_water / f0;

% 强制各项同性网格
dx = Lx / Nx; 
dy = dx; 
dz = dx; 

Lz_needed = 30e-3; 
% 2. 换算为基础网格数
Nz_min = ceil(Lz_needed / dz);

optimal_sizes = [128, 192, 216, 256, 300, 384, 512];
Nz = optimal_sizes(find(optimal_sizes >= Nz_min, 1));

Lz = Nz * dz;
% ==================================================

x = (-Nx/2 : Nx/2-1) * dx;

% 打印诊断信息，确保没有浪费算力
fprintf('==================================================\n');
fprintf('网格分辨率: dx = dy = dz = %.4f mm\n', dx*1e3);
fprintf('每波长采样点 (PPW): %.2f (建议 > 3)\n', lambda_water/dx);
fprintf('优化后网格尺寸: %d x %d x %d (总节点数: %.1f 百万)\n', Nx, Ny, Nz, (Nx*Ny*Nz)/1e6);
fprintf('Z轴物理长度缩减至: %.2f mm\n', Lz*1e3);
fprintf('==================================================\n');

%% === 2. 目标图案几何定义 (万能校徽平台版) ===
% [平台化更改]：彻底废除硬编码 A 的逻辑，改为通用的图像文件读取与处理接口。
% 此模块天生适应任何复杂结构，只需保证文件存在即可自动缩放、居中并单精度化。

% 1. 物理图像导入与预处理
% 我们假设你已经将该校徽图片保存为 'image_6.png' 并放置在 MATLAB 当前目录下。
% 我们在 Github 上管理代码时，必须确保此图片文件也同时存在。
logo_filename = "C:\Users\Zh89\Desktop\transport\a3-1jdxhred.png"; 

if ~exist(logo_filename, 'file')
    error('❌ 找不到目标图案文件 %s！请确保文件存在并放置在代码所在的 Github 仓库当前目录中。', logo_filename);
end

% 读取 RGB 图像并提取红光分量 (因为输入校徽图案是红色的)
% 如果未来换了其他颜色的图，系统会自动适配非黑色区域。
logo_rgb = imread(logo_filename);
if size(logo_rgb, 3) == 3
    % 红色校徽，提取第一通道 (Red Channel)
    logo_base = logo_rgb(:,:,1);
else
    % 如果已经是灰度图，直接使用
    logo_base = logo_rgb;
end

% 2. 动态二值化处理 (核心平台逻辑)
% 物理真相：声学目标不仅仅包括中间的红色图案，甚至还要包括不规则的边缘。
% 只要是非纯黑 (背景) 区域，都视为声学目标，都标记为 1 (Target Voxel)。
% 我们设定一个极低的阈值 (10/255) 来精确保留校徽复杂结构的边缘细节，同时抑制非黑背景中的微小噪点。
logo_bw_raw = logo_base > 10;

% 为了匹配 IASA 和角谱传播的物理坐标系，我们将 imread 的结果进行上下翻转。
% 因为 imread 的第 1 行是图像顶部 (Max Y)，我们需要让其对应物理空间的 Max Y。
% 同时进行上下和左右翻转，确保文字在物理空间中是正向的
logo_bw_flipped = fliplr(flipud(logo_bw_raw));
% 3. 尺寸定标与缩放 (适应任何复杂结构的关键环节)
% 平台原则：不管输入的图案多复杂、诡异，系统会自动将其按比例缩放至适应 Nx * Ny 大小。
[h_logo_px, w_logo_px] = size(logo_bw_flipped);

% 定义填充系数：目标图案应当占整个模拟空间 Y 轴高度的 60%，预留足够的 PML 安全边界。
target_fill_ratio_y = 0.6;
scale_factor = (Ny * target_fill_ratio_y) / h_logo_px;

% 使用最近邻插值 (nearest neighbor) 缩放，确保二值矩阵边缘依然锐利，拒绝任何由于模糊产生的中间像素。
logo_scaled_bw = imresize(logo_bw_flipped, scale_factor, 'nearest');

% 4. 居中对齐与物理场生成
imag_target = zeros(Nx, Ny, 'single'); % 初始化标准 2D 单精度靶标振幅场矩阵
[h_sc_px, w_sc_px] = size(logo_scaled_bw);

% 检查缩放后是否超出了 Nx * Ny 的限制
if h_sc_px > Nx || w_sc_px > Ny
    error('❌ 输入图案缩放后 (Px: %dx%d) 依然超出了模拟网格 (Px: %dx%d) 的限制！请减小 target_fill_ratio_y 或手动缩小原图。', ...
        h_sc_px, w_sc_px, Nx, Ny);
end

start_r = round((Nx - h_sc_px) / 2) + 1; % 加1匹配 MATLAB 索引
start_c = round((Ny - w_sc_px) / 2) + 1;

% 将缩放、居中后的校徽二值掩膜填入单精度矩阵。
% 这一矩阵将直接作为 Python PANN 炼丹的终极输入。
imag_target(start_r : start_r + h_sc_px - 1, ...
            start_c : start_c + w_sc_px - 1) = single(logo_scaled_bw);
% ... [前面读取和缩放校徽的代码保持不变] ...

imag_target(start_r : start_r + h_sc_px - 1, ...
            start_c : start_c + w_sc_px - 1) = single(logo_scaled_bw);

% 🚀 核心拯救：物理级靶标预处理 (抑制散斑的终极杀器)
% 用高斯滤波主动抹平数学上的绝对直角，使其符合声波的衍射极限。
% 这样 IASA 算法就不会为了死磕边缘而产生满屏的高频散斑！
sigma_blur = 1.5; % 模糊半径 (可微调，1.0~2.0之间)
imag_target = imgaussfilt(imag_target, sigma_blur);
% 确保归一化在 0~1 之间
imag_target = imag_target ./ max(imag_target(:)); 

% 5. 平台级物理参数预统计...

% 5. 平台级物理参数预统计
ROI_pixels = sum(imag_target(:) > 0.5);
fprintf('📦 万能靶标发生器接口：校徽图案已成功转化为二值矩阵！\n');
fprintf('   当前 ROI 像素数 (打印区域体素): %d node.\n', ROI_pixels);
fprintf('   模拟区域分辨率: %.2f μm.\n', dx*1e6);
fprintf('========================================\n');% === 1. 导出靶标数据到专属中转站 ===
    transport_dir = 'C:\Users\Zh89\Desktop\transport';
    if ~exist(transport_dir, 'dir')
        mkdir(transport_dir);
    end
    
    export_path = fullfile(transport_dir, 'target_for_python.mat');
    save(export_path, 'imag_target', 'Nx', 'Ny', 'Lx', 'lambda_water', 'z_target_dist');
    
    disp('按下【回车键 (Enter)】继续读取 Python 的结果...');
    pause; % 程序会在这里完全挂起，直到你敲击键盘
    
    fprintf('\n🚀 收到继续指令！正在检查中转站...\n');
%% === 3. IASA 迭代 (接收深度学习快递) ===
fprintf('运行 PANN-IASA 混合架构收敛...\n');

% 定义中转站路径
transport_dir = 'C:\Users\Zh89\Desktop\transport';
import_path = fullfile(transport_dir, 'dl_phase_init.mat');

% 防呆检测：确保 Python 已经跑完了
if ~exist(import_path, 'file')
    error('❌ 中转站里没有找到 dl_phase_init.mat！请确认 Python 脚本是否成功运行。');
end

% 加载深度学习生成的初始相位
load(import_path, 'optimal_initial_phase');
fprintf('📦 成功从中转站提取神级初始相位！准备起飞...\n');
% ... 接下来的 target_pad 定义和 epoch=150 的循环，完全保持你原样 ...
pad_factor = 2; 
Nx_pad = Nx * pad_factor; 
Ny_pad = Ny * pad_factor;
Lx_pad = Lx * pad_factor;
dk_pad = 2 * pi / Lx_pad;
kx_pad = (-Nx_pad/2 : Nx_pad/2-1) * dk_pad;
[Kx_pad, Ky_pad] = meshgrid(kx_pad, kx_pad);

k_water = 2 * pi / lambda_water;
Kz_sq = k_water^2 - Kx_pad.^2 - Ky_pad.^2;
Kz_sq(Kz_sq < 0) = 0; 
H_forward = exp(1i * sqrt(Kz_sq) * z_target_dist); 
H_backward = exp(-1i * sqrt(Kz_sq) * z_target_dist); 
    board_phase_pad = zeros(Nx_pad, Ny_pad);
    board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = exp(1i * optimal_initial_phase);

target_pad = zeros(Nx_pad, Ny_pad);
target_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = imag_target;
weight_pad = target_pad * 1.5; 
mask_roi = (target_pad > 0.5);     
mask_dark = (target_pad < 0.5);    

epoch = 150; 
for i = 1:epoch
    U_source = zeros(Nx_pad, Ny_pad);
    center_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));
    U_source(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = 1.0 .* exp(1i * center_phase);
    
    A_source = fftshift(fft2(ifftshift(U_source)));
    A_target = A_source .* H_forward;
    U_target = fftshift(ifft2(ifftshift(A_target)));
    
    rec_amp = abs(U_target);
    peak_val = max(rec_amp(mask_roi)); 
    if peak_val == 0, peak_val = max(rec_amp(:)); end
    rec_amp_norm = rec_amp / peak_val;
    
    if i > 5
        beta = 0.8; 
        correction = (target_pad(mask_roi) ./ (rec_amp_norm(mask_roi) + 1e-6)) .^ beta;
        weight_pad(mask_roi) = weight_pad(mask_roi) .* correction;
        weight_pad(weight_pad > 10) = 10;
        weight_pad(mask_dark) = 0;
    end
    current_weight = weight_pad; 
    U_target_constrained = weight_pad .* exp(1i * angle(U_target));
    A_target_cons = fftshift(fft2(ifftshift(U_target_constrained)));
    A_source_cons = A_target_cons .* H_backward;
    U_source_new = fftshift(ifft2(ifftshift(A_source_cons)));
    
    board_phase_pad = U_source_new;
end

holo_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));
figure(1);
subplot(1,2,1); imagesc(x*1e3, x*1e3, imag_target); axis image; colormap gray; title('目标');
subplot(1,2,2); imagesc(x*1e3, x*1e3, holo_phase); axis image; colormap jet; title('IASA 相位 (Pad优化)');

%% === [修改部分 Start] 相位转厚度与体素化优化 ===

phase_wrapped = mod(holo_phase, 2*pi); 

k_board_val = 2 * pi * f0 / c_board;
k_water_val = 2 * pi * f0 / c_water;
k_diff = abs(k_water_val - k_board_val); 

thickness_ideal = phase_wrapped / k_diff;

% [微平滑]：sigma 设为非常小的值，仅消除孤立的像素点突变
thickness_map = imgaussfilt(thickness_ideal, 0.2); 
min_base = 2 * dz; 
thickness_map = thickness_map + min_base;

% 严格体素化
net_num_board = round(thickness_map / dz);
actual_thickness = net_num_board * dz;

% 反算理论相位
actual_phase_imparted = mod(actual_thickness * k_diff, 2*pi);
complex_diff_voxel = exp(1i * actual_phase_imparted) ./ exp(1i * phase_wrapped);
global_offset_voxel = angle(mean(complex_diff_voxel(:))); 
phase_aligned_voxel = angle(exp(1i * (actual_phase_imparted - global_offset_voxel)));

% 计算理论量化误差
phase_error_voxel = abs(angle(exp(1i * (phase_aligned_voxel - phase_wrapped))));
mean_phase_error = mean(phase_error_voxel(:));
max_phase_error = max(phase_error_voxel(:));
fprintf(' -> 理论体素化平均相位误差: %.4f Rad (%.1f 度)\n', mean_phase_error, mean_phase_error*180/pi);

figure(11); clf;
set(gcf, 'Position', [100, 100, 1200, 400], 'Color', 'w');
subplot(1,3,1); imagesc(x*1e3, x*1e3, phase_wrapped); axis image; colormap hsv; colorbar; title('理想 Wrapped 相位');
subplot(1,3,2); imagesc(x*1e3, x*1e3, phase_aligned_voxel); axis image; colormap hsv; colorbar; title('微平滑体素化实际相位');
subplot(1,3,3); surf(x*1e3, x*1e3, actual_thickness*1e3); shading flat; colormap parula; title('构建的 3D 透镜厚度'); view(2); colorbar;

%% k-Wave 介质建模
fprintf('仿真环境与实体介质构建\n');
kgrid = kWaveGrid(Nx, dx, Ny, dy, Nz, dz);
medium.sound_speed = c_water * ones(Nx, Ny, Nz);

% [关键物理隔离]：为了证明是网格散射惹的祸，而不是材料反射
% 我们强行关闭材料的阻抗失配！即：保持声速不同以产生相位差，但让密度补偿以匹配水的声阻抗。
% 声阻抗 Z = rho * c。我们希望 Z_board = Z_water
% rho_match = (c_water * density_water) / c_board;

medium.density = density_water * ones(Nx, Ny, Nz);
medium.alpha_coeff = 0.002 * ones(Nx, Ny, Nz); 
medium.alpha_power = 1.5;

pml_size = 10;
source_z_idx = pml_size + 5;
z_board_stat_idx = source_z_idx + 2;

fprintf('将透镜写入 3D 网格...\n');
for i = 1:Nx
    for j = 1:Ny
        n_layers = net_num_board(i, j);
        if n_layers > 0
            z_start = z_board_stat_idx;
            z_end = z_board_stat_idx + n_layers - 1;
            
            medium.sound_speed(i, j, z_start:z_end) = c_board;
            
            % 使用阻抗匹配的密度，消除内部反射
            medium.density(i, j, z_start:z_end) = density_board; 
            
            % 为了看清纯粹的相位作用，暂时关闭树脂的额外衰减
            % medium.alpha_coeff(i, j, z_start:z_end) = 1.0; 
        end
    end
end
thickest = max(net_num_board(:)) * dz;
% === [修改部分 End] ===
%% 时间 (保持原样)
fprintf('时间设置\n');
cfl = 0.3;
t_end = (Lz * 1.5) / c_water; 
kgrid.makeTime(medium.sound_speed, cfl, t_end); 

%% 6. 声源定义 
% === [修改部分 Start] 恢复为平面波声源 ===
% 原逻辑直接加了相位，这里因为已经有物理透镜，必须使用无相位的平面波
source.p_mask = zeros(Nx, Ny, Nz);
source.p_mask(:, :, source_z_idx) = 1; 
fprintf('构建平面波声源 (相位由物理透镜调制)\n');
t_vec = kgrid.t_array;
source_sig = sin(2 * pi * f0 * t_vec); % 纯正弦波

% 加一个简单的斜坡窗减少瞬态冲击
ramp_pts = round(2 / f0 / kgrid.dt); 
window = [linspace(0,1,ramp_pts), ones(1, kgrid.Nt-ramp_pts)];
source.p = source_sig .* window;
source.p_mode = 'dirichlet';
% === [修改部分 End] ===

%% 7. Sensor 放置
% === [修改部分 Start] 同时放置出口平面与目标平面的Sensor ===
fprintf('sensor设置\n');
sensor.mask = zeros(Nx, Ny, Nz);

% 1. 记录出口平面 (用于校验透镜转换质量)
 z_board_exit_idx = z_board_stat_idx + round(thickest/dz);
% sensor.mask(:, :, z_board_exit_idx) = 1;

% 2. 记录目标平面 (用于量化评估)
target_plane_idx = z_board_exit_idx + round(z_target_dist / dz);
scan_range_idx = round(3e-3 / dz); 
z_scan_start = target_plane_idx - scan_range_idx;
z_scan_end = target_plane_idx + scan_range_idx;

% 安全检查防止越界
if z_scan_end > Nz - pml_size
    z_scan_end = Nz - pml_size;
end
sensor.mask(:, :, z_scan_start:z_scan_end) = 1;

% 🚀 【绝杀修改点】：从 'p' 变更为 'p_max'
        % 这让 k-Wave 只提取每个网格的物理振幅，彻底抛弃庞大的时间维度！内存占用瞬间降至 1/50！
        sensor.record = {'p_max'}; 
        sensor.record_start_index = kgrid.Nt - round(3/f0/kgrid.dt);
% fprintf('  - 出口校验面 Z Index: %d\n', z_board_exit_idx);
fprintf('  - 扫描范围 Z Index: %d 到 %d (寻找物理最佳焦面)\n', z_scan_start, z_scan_end);
% fprintf('  - 目标平面 Z Index: %d (距离源 %.2f mm)\n', target_plane_idx, target_plane_idx*dz*1e3);
% === [修改部分 End] ===

%% 8. 仿真 (保持原样)
fprintf('仿真开始\n');
input_args = {
    'PMLInside', true, ...
    'PMLSize', 10, ...
    'PlotPML', false, ...
    'PlotSim', false, ...
    'DataCast', 'gpuArray-single' 
};
try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch
    disp('GPU 失败，切换 CPU...');
    input_args = input_args(1:end-2);
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
end

%% 9. 数据处理与量化评估 (新增自动 Z-Scan 寻优逻辑 - 极速版)
if isfield(sensor_data, 'p_max')
    % 🚀 直接提取 k-Wave 底层计算好的稳态振幅场，绕过消耗 8GB 内存的 FFT！
    p_amp = gather(sensor_data.p_max); 
    
    p_field_3d = zeros(Nx, Ny, Nz);
    mask_indices = find(sensor.mask);
    p_field_3d(mask_indices) = p_amp; % 此时 p_field_3d 已经是纯振幅矩阵
    
    % 提取扫描体积的声压幅值
    scan_vol = p_field_3d(:, :, z_scan_start:z_scan_end);
    num_slices = size(scan_vol, 3);
    
    % --- 准备目标图像进行评估 ---
    R = double(imag_target);                 
    R = (R - min(R(:))) / (max(R(:)) - min(R(:)));
    R_mean = mean(R(:));
    
    best_corr = -1;
    best_slice_idx = 1;
    best_img_recon = [];
    best_nmse = inf;
    best_psnr = 0;
    
    % 新增：记录每一层的指标，用于 Z-Scan 曲线绘制
    metrics_z = zeros(num_slices, 1);
    metrics_corr = zeros(num_slices, 1);
    
    fprintf('开始 Z-Scan 寻优...\n');
    % 逐层计算相关系数，寻找真正聚焦最完美的平面
    for k = 1:num_slices
        A = scan_vol(:, :, k);
        A = (A - min(A(:))) / (max(A(:)) - min(A(:))); % 归一化
        A_mean = mean(A(:));
        
        % 计算 Correlation
        numerator = sum(sum((R - R_mean) .* (A - A_mean)));
        denominator = sqrt(sum(sum((R - R_mean).^2)) * sum(sum((A - A_mean).^2)));
        val_corr = numerator / denominator;
        
        % 记录到数组
        metrics_z(k) = (z_scan_start + k - 1 - z_board_exit_idx) * dz * 1e3;
        metrics_corr(k) = val_corr;
        
        if val_corr > best_corr
            best_corr = val_corr;
            best_slice_idx = k;
            best_img_recon = A;
            
            % 同步记录最高 Corr 时的其他指标
            best_nmse = sum(sum((R - A).^2)) / sum(sum(R.^2));
            mse = mean((R(:) - A(:)).^2);
            if mse == 0, best_psnr = Inf; else, best_psnr = 20 * log10(1 / sqrt(mse)); end
        end
    end
    
    % [核心修复]：计算在全空间 3D 矩阵中的绝对 Z 轴索引，供热力学引擎使用
    best_idx_global = z_scan_start + best_slice_idx - 1;
    
    % 计算实际的最佳物理聚焦距离
    actual_z_dist_idx = best_idx_global - z_board_exit_idx;
    actual_z_dist_mm = actual_z_dist_idx * dz * 1e3;
    
    fprintf('>>> 自动寻优完成！最佳焦面发生偏移: 理论 20.00mm -> 实际 %.2f mm\n', actual_z_dist_mm);
end

%% 12. 原生 3D FDTD 热扩散仿真 (空化屏蔽饱和模型 + 色标修复)
fprintf('\n========================================\n');
fprintf('启动原生 3D 热扩散 FDTD 求解器 (GPU 极速版)...\n');
%% 12. 原生 3D FDTD 自适应寻优引擎 (粗细双阶 + 能量启发式剪枝)
fprintf('\n========================================\n');
fprintf('🚀 启动 3D 非均匀介质【粗细双阶自适应】寻优引擎...\n');

% --- 1. 物理场真实功率注入 (基准定标) ---
p_3d_abs = abs(p_field_3d); 
focal_slice_abs = p_3d_abs(:, :, best_idx_global);
roi_mask = (imag_target > 0.5);
median_roi_p = median(focal_slice_abs(roi_mask)); 

% 1. 将 A 内部的平均声压定标为 1.2 MPa (刚好引发产热)
target_median_pressure = 2e6;
cavitation_limit = 2.0e6;
exposure_time = 0.24;

scale_factor = target_median_pressure / median_roi_p;
p_3d_scaled = p_3d_abs * scale_factor;

% 2. [终极真实物理约束]：水中的声空化饱和效应 (Cavitation Shielding)
% 任何超过 2.0 MPa 的能量都会被气泡散射，绝对无法参与深层加热！
 
p_3d_scaled(p_3d_scaled > cavitation_limit) = cavitation_limit; 

rho_resin = 1100;  c_resin = 2500;  Cp_resin = 1500;  k_resin = 0.2; 
rho_water = 997;   c_water = 1480;  Cp_water = 4180;  k_water = 0.6; 
alpha_np_resin = (1.5 / 8.686) * 100 * (f0/1e6)^1.5; 
% --- 2. 基础材料属性设定 ---
rho_resin = 1100;  c_resin = 2500;  Cp_resin_liq = 1800;  k_resin_liq = 0.15; 
rho_water = 997;   c_water = 1480;  Cp_water = 4180;      k_water = 0.6; 
alpha_np_resin_liq = (1.5 / 8.686) * 100 * (f0/1e6)^1.5; 
alpha_np_water = 0.02; 
resin_z_start = z_board_exit_idx + 1;
cavitation_limit = 2.0e6;

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

% --- 2. Z轴物理截断与 GPU 载入 ---
E_a = 9.5e4; A_freq = 8.0e15; R_gas = 8.314;
inv_dx2 = 1 / (dx^2);
max_diff = max(k_water/(rho_water*Cp_water), k_resin_liq/(rho_resin*Cp_resin_liq));
dt_th = (dx^2 / (6 * max_diff)) * 0.8; 

z_crop_radius = round(1.5e-3 / dz); 
z_crop_start = max(1, best_idx_global - z_crop_radius);
z_crop_end = min(Nz, best_idx_global + z_crop_radius);
best_idx_crop = best_idx_global - z_crop_start + 1;
z_crop_len = z_crop_end - z_crop_start + 1;


try
    T_3d_gpu = gpuArray(50 * ones(Nx, Ny, z_crop_end - z_crop_start + 1, 'single'));
    diffusivity_gpu = gpuArray(diffusivity_3d(:, :, z_crop_start:z_crop_end));
    dT_source_gpu = gpuArray(dT_source_3d(:, :, z_crop_start:z_crop_end));
catch
    T_3d_gpu = 50 * ones(Nx, Ny, z_crop_end - z_crop_start + 1, 'single');
    diffusivity_gpu = diffusivity_3d(:, :, z_crop_start:z_crop_end);
    dT_source_gpu = dT_source_3d(:, :, z_crop_start:z_crop_end);
end

% --- 3. 极速 FDTD 演化 (植入 Arrhenius 动力学引擎) ---
max_diffusivity = max(k_resin/(rho_resin*Cp_resin), k_water/(rho_water*Cp_water));
dt_th_max = (dx^2) / (6 * max_diffusivity);
dt_th = dt_th_max * 0.9; 
Nt_th = round(exposure_time / dt_th);

num_snapshots = 5;
snapshot_steps = round(linspace(1, Nt_th, num_snapshots));
snapshots_2d = zeros(Nx, Ny, num_snapshots);
T_max_history = zeros(Nt_th, 1);
t_axis = (1:Nt_th) * dt_th;

% 🚀 [新增核心]：Arrhenius 动力学常数初始化
E_a = 9.5e4;           % 活化能 (J/mol)，代表触发交联所需的能量门槛
A_freq = 5.0e15;       % 频率因子 (1/s)，代表分子碰撞频率
R_gas = 8.314;         % 理想气体常数 (J/(mol*K))
Arrhenius_Omega_gpu = gpuArray(zeros(Nx, Ny, 'single')); % GPU 上的累积热剂量矩阵

fprintf('  演化中 (ROI 定标 1.2MPa, 空化上限 2.0MPa, 启动 Arrhenius 积分)...\n');
tic;
for step = 1:Nt_th
    % 1. 解热传导偏微分方程
    laplacian_T = 6 * del2(T_3d_gpu, dx);
    T_3d_gpu = T_3d_gpu + dt_th * (diffusivity_gpu .* laplacian_T + dT_source_gpu);
    
    % 取出当前时刻的焦面温度分布
    T_focal_slice = T_3d_gpu(:, :, best_idx_crop);
    T_max_history(step) = gather(max(T_focal_slice(:)));
    
    % 🚀 [新增核心]：在时间循环中，实时积分累积反应度 (Omega)
    % 将摄氏度转换为绝对开尔文温度
    T_current_K = T_focal_slice + 273.15; 
    % 计算当前瞬态温度下的化学反应速率 k(T)
    reaction_rate = A_freq .* exp(-E_a ./ (R_gas .* T_current_K));
    % 时间积分：累加到反应度矩阵中
    Arrhenius_Omega_gpu = Arrhenius_Omega_gpu + reaction_rate .* dt_th;
    
    % 记录快照
    snap_idx = find(snapshot_steps == step);
    if ~isempty(snap_idx)
        snapshots_2d(:, :, snap_idx) = gather(double(T_focal_slice));
    end
end
fprintf('  >>> 热力学与动力学演化耗时: %.2f 秒\n', toc);

T_focal_2d = gather(double(T_3d_gpu(:, :, best_idx_crop)));
T_max_real = T_max_history(end);
Q_focal_2d = gather(double(dT_source_gpu(:, :, best_idx_crop) * rho_resin * Cp_resin));

% 提取最终的反应度分布矩阵回 CPU
Omega_final_2d = gather(double(Arrhenius_Omega_gpu));

% 13. 基于真实动力学的形貌预测 (废除绝对温度阈值)
% 物理意义：当累积热剂量 Omega >= 1.0 时，认为材料分子链已完成交联网络构建

% 寻优历史记录容器
best_IoU_global = 0;
best_record = struct();
best_coarse = struct('P', 1.5e6, 'E', 0.3, 'C', 0.2); % 初始化粗搜最佳占位符

% 🔄 双阶寻优大循环 (Phase 1: 粗扫大地图, Phase 2: 细扫甜点区)
for phase = 1:2
    if phase == 1
        fprintf('\n🟢 [第一阶段: 全局粗扫] 寻找物理能量甜点区...\n');
        P_list = (1.2 : 0.2 : 1.8) * 1e6;   % 声压大步长: 1.2, 1.4, 1.6, 1.8 MPa
        E_list = 0.15 : 0.10 : 0.45;        % 照射大步长: 0.15, 0.25, 0.35, 0.45s
        C_list = 0.10 : 0.10 : 0.30;        % 冷却大步长: 0.10, 0.20, 0.30s
    else
        fprintf('\n🔴 [第二阶段: 局部微调] 围绕粗搜最优点 (P=%.2f, E=%.2f, C=%.2f) 进行极限压榨...\n', ...
            best_coarse.P/1e6, best_coarse.E, best_coarse.C);
        % 围绕第一阶段找出的最优点，极小步长散开
        P_list = (best_coarse.P - 0.1e6) : 0.05e6 : (best_coarse.P + 0.1e6);
        E_list = max(0.10, best_coarse.E - 0.05) : 0.02 : (best_coarse.E + 0.05);
        C_list = max(0.05, best_coarse.C - 0.05) : 0.05 : (best_coarse.C + 0.05);
    end
    
    % 生成全排列网格
    [Pg, Eg, Cg] = ndgrid(P_list, E_list, C_list);
    params_all = [Pg(:), Eg(:), Cg(:)];
    
    % 🔪 启发式能量剪枝 (Heuristic Pruning)
    % 能量代理指数 Energy Index ~ (P_MPa)^2 * t_exp
    energy_index = (params_all(:,1)/1e6).^2 .* params_all(:,2);
    % 物理法则：指数 < 0.3 绝对烤不熟；指数 > 1.2 绝对糊成一团，直接丢弃！
    valid_mask = (energy_index >= 0.3) & (energy_index <= 1.2);
    params_valid = params_all(valid_mask, :);
    
    % 按照声压排序，避免重复计算声场和热源，大幅节省时间
    params_valid = sortrows(params_valid, 1);
    num_tests = size(params_valid, 1);
    
    fprintf('   本阶段有效组合数: %d (已剪枝掉 %d 组无意义参数)\n', num_tests, length(energy_index) - num_tests);
    
    current_P = -1; % 用于记录当前声压状态
    
    for i = 1:num_tests
        p_target = params_valid(i, 1);
        t_exp = params_valid(i, 2);
        t_cool = params_valid(i, 3);
        
        % [GPU 加速技巧] 只有当声压发生变化时，才重新计算 3D 热源场
        if p_target ~= current_P
            scale_factor = p_target / median_roi_p;
            p_3d_scaled = p_3d_abs * scale_factor;
            p_3d_scaled(p_3d_scaled > cavitation_limit) = cavitation_limit; 
            
            k_3d = k_water * ones(Nx, Ny, Nz, 'single');
            k_3d(:, :, resin_z_start:end) = k_resin_liq;
            rho_Cp_3d = (rho_water * Cp_water) * ones(Nx, Ny, Nz, 'single');
            rho_Cp_3d(:, :, resin_z_start:end) = rho_resin * Cp_resin_liq;
            
            Q_heat_3d = zeros(Nx, Ny, Nz, 'single');
            I_3d_resin = single((p_3d_scaled(:, :, resin_z_start:end).^2) ./ (2 * rho_resin * c_resin));
            Q_heat_3d(:, :, resin_z_start:end) = 2 * alpha_np_resin_liq * I_3d_resin;
            I_3d_water = single((p_3d_scaled(:, :, 1:resin_z_start-1).^2) ./ (2 * rho_water * c_water));
            Q_heat_3d(:, :, 1:resin_z_start-1) = 2 * alpha_np_water * I_3d_water;
            
            k_3d_base_gpu = gpuArray(k_3d(:, :, z_crop_start:z_crop_end));
            rho_Cp_3d_gpu = gpuArray(rho_Cp_3d(:, :, z_crop_start:z_crop_end));
            Q_heat_3d_gpu = gpuArray(Q_heat_3d(:, :, z_crop_start:z_crop_end));
            
            current_P = p_target;
        end
        
        % ---------------- FDTD 演化核心 ----------------
        total_time = t_exp + t_cool;
        Nt_th = round(total_time / dt_th);
        step_exposure_end = round(t_exp / dt_th);
        
        T_3d_gpu = 25 * ones(Nx, Ny, z_crop_len, 'single', 'gpuArray');
        k_3d_gpu = k_3d_base_gpu;
        Arrhenius_Omega_gpu = zeros(Nx, Ny, 'single', 'gpuArray'); 
        T_max_history_tmp = zeros(Nt_th, 1);
        
        for step = 1:Nt_th
            chi_focal = 1.0 - exp(-Arrhenius_Omega_gpu);
            k_3d_gpu(:, :, best_idx_crop) = k_resin_liq * (1.0 + 0.6 * chi_focal);
            
            T_diff_x = diff(T_3d_gpu, 1, 1);
            k_mid_x = (k_3d_gpu(1:end-1,:,:) + k_3d_gpu(2:end,:,:)) / 2;
            div_flux_x = diff([zeros(1,Ny,z_crop_len,'single','gpuArray'); k_mid_x .* T_diff_x; zeros(1,Ny,z_crop_len,'single','gpuArray')], 1, 1);
            
            T_diff_y = diff(T_3d_gpu, 1, 2);
            k_mid_y = (k_3d_gpu(:,1:end-1,:) + k_3d_gpu(:,2:end,:)) / 2;
            div_flux_y = diff([zeros(Nx,1,z_crop_len,'single','gpuArray'), k_mid_y .* T_diff_y, zeros(Nx,1,z_crop_len,'single','gpuArray')], 1, 2);
            
            T_diff_z = diff(T_3d_gpu, 1, 3);
            k_mid_z = (k_3d_gpu(:,:,1:end-1) + k_3d_gpu(:,:,2:end)) / 2;
            div_flux_z = diff(cat(3, zeros(Nx,Ny,1,'single','gpuArray'), k_mid_z .* T_diff_z, zeros(Nx,Ny,1,'single','gpuArray')), 1, 3);

            thermal_diffusion_term = (div_flux_x + div_flux_y + div_flux_z) ./ rho_Cp_3d_gpu * inv_dx2;

            if step <= step_exposure_end
                abs_multiplier = 1.0 + 3.0 * chi_focal; 
                Q_dynamic = Q_heat_3d_gpu;
                Q_dynamic(:, :, best_idx_crop) = Q_heat_3d_gpu(:, :, best_idx_crop) .* abs_multiplier;
                T_3d_gpu = T_3d_gpu + dt_th * (thermal_diffusion_term + Q_dynamic ./ rho_Cp_3d_gpu);
            else
                T_3d_gpu = T_3d_gpu + dt_th * thermal_diffusion_term;
            end
            
            T_focal_slice = T_3d_gpu(:, :, best_idx_crop);
            T_max_history_tmp(step) = gather(max(T_focal_slice(:)));
            T_current_K = T_focal_slice + 273.15; 
            reaction_rate = A_freq .* exp(-E_a ./ (R_gas .* T_current_K));
            Arrhenius_Omega_gpu = Arrhenius_Omega_gpu + reaction_rate .* dt_th;
        end
        
        % ---------------- 提取指标与打擂台 ----------------
        Omega_tmp = gather(double(Arrhenius_Omega_gpu));
        cured_mask_tmp = (Omega_tmp >= 1.0);
        target_mask_2d = double(imag_target > 0.5);
        intersection = sum(cured_mask_tmp(:) & target_mask_2d(:));
        union_area = sum(cured_mask_tmp(:) | target_mask_2d(:));
        current_IoU = intersection / (union_area + 1e-10);
        
        fprintf('  [%02d/%02d] P=%.2fMPa, 照=%.2fs, 冷=%.2fs | Max Temp: %4.1f°C | IoU: %.4f\n', ...
            i, num_tests, p_target/1e6, t_exp, t_cool, max(T_max_history_tmp), current_IoU);
            
        if current_IoU > best_IoU_global
            best_IoU_global = current_IoU;
            % 记录到全局最佳
            best_record.p_target = p_target; best_record.t_exp = t_exp; best_record.t_cool = t_cool;
            best_record.T_focal_2d = gather(double(T_3d_gpu(:, :, best_idx_crop)));
            best_record.Q_focal_2d = gather(double(Q_heat_3d_gpu(:, :, best_idx_crop)));
            best_record.Omega_final_2d = Omega_tmp;
            best_record.T_max_history = T_max_history_tmp;
            best_record.Nt_th = Nt_th; best_record.p_3d_scaled = p_3d_scaled;
            % 同时也记录到该阶段的最佳，供给第二阶段使用
            if phase == 1
                best_coarse.P = p_target; best_coarse.E = t_exp; best_coarse.C = t_cool;
            end
        end
    end
end

fprintf('\n🏆 全局自适应寻优彻底结束！最终【天命参数】出炉：\n');
fprintf('   👑 最优定标声压: %.2f MPa\n', best_record.p_target / 1e6);
fprintf('   👑 最优照射时间: %.2f 秒\n', best_record.t_exp);
fprintf('   👑 最优冷却时间: %.2f 秒\n', best_record.t_cool);
fprintf('   🔥 极限压榨 IoU: %.4f\n', best_IoU_global);
fprintf('========================================\n');

% 将天命参数覆盖全局变量
target_median_pressure = best_record.p_target;
exposure_time = best_record.t_exp; cooling_time = best_record.t_cool;
T_focal_2d = best_record.T_focal_2d; Q_focal_2d = best_record.Q_focal_2d;
Omega_final_2d = best_record.Omega_final_2d; T_max_history = best_record.T_max_history;
Nt_th = best_record.Nt_th; p_3d_scaled = best_record.p_3d_scaled;
t_axis = (1:Nt_th) * dt_th; T_max_real = max(T_max_history);

% 13. 基于真实动力学的形貌预测
Thermal_Dose_Threshold = 1.0; 

% 现在的判定标准变成了动力学积分量！
cured_mask_2d = Omega_final_2d >= Thermal_Dose_Threshold;

ROI_pixels = sum(imag_target(:) > 0.5); 
cured_coverage = (sum(cured_mask_2d(:)) / ROI_pixels) * 100; 
if cured_coverage > 100, cured_coverage = 100; end

R_binary = imag_target > 0.5;
intersection = R_binary & cured_mask_2d;
union = R_binary | cured_mask_2d;
IoU = sum(intersection(:)) / sum(union(:));

% 14. 终极可视化全景仪表盘 (Arrhenius 动力学与纯净绘图版)
y = x; 

% --- 图 1：热演化时间切片 ---
figure(88); clf; set(gcf, 'Position', [100, 100, 1400, 500], 'Color', 'w');
for i = 1:num_snapshots
    subplot(2, num_snapshots, i);
    imagesc(x*1e3, y*1e3, snapshots_2d(:, :, i));
    axis image off; colormap hot; 
    caxis([50, max(65, min(T_max_real, 120))]); 
end
subplot(2, 1, 2);
plot(t_axis, T_max_history, 'r-', 'LineWidth', 2); hold on;
% 现在的 65 度仅仅是参考线，不再是绝对阈值
yline(65, 'k--', 'LineWidth', 1.5); 
grid on; set(gca, 'Color', 'w');
ylim([20, max(max(T_max_history)+10, 80)]);

% --- 图 2：多物理场核心全景 ---
figure('Position', [30 30 1500 1000], 'Color', 'w');

subplot(3, 5, 1);
imagesc(x*1e3, y*1e3, imag_target); axis image off; colormap(gca, gray);

subplot(3, 5, 2);
imagesc(x*1e3, y*1e3, phase_wrapped); axis image off; colormap(gca, hsv);

subplot(3, 5, 3);
imagesc(x*1e3, y*1e3, phase_aligned_voxel); axis image off; colormap(gca, hsv);

subplot(3, 5, 4);
surf(x*1e3, y*1e3, actual_thickness*1e3); view(2); shading interp; axis image off;

% 🚀 [核心升级] 引入 Arrhenius 热剂量分布图 (替换了原本的 weight_pad)
subplot(3, 5, 5);
imagesc(x*1e3, y*1e3, Omega_final_2d); axis image off; colormap(gca, turbo);
% 将 1.0 的阈值卡在色标极具对比度的中间位置
caxis([0, max(2.0, max(Omega_final_2d(:)))]); 

subplot(3, 5, 6);
imagesc(x*1e3, y*1e3, Q_focal_2d / 1e6); axis image off; colormap(gca, hot);

subplot(3, 5, 7);
p_focal_scaled = gather(p_3d_scaled(:, :, best_idx_global));
imagesc(x*1e3, y*1e3, p_focal_scaled/1e6); axis image off; colormap(gca, jet);

% 🚀 固化形貌采用纯白背景与深色目标映射
subplot(3, 5, 8);
imagesc(x*1e3, y*1e3, cured_mask_2d); axis image off;
colormap(gca, [1 1 1; 0.1 0.1 0.3]); 

subplot(3, 5, 9);
imagesc(x*1e3, y*1e3, T_focal_2d); axis image off; colormap(gca, hot);
caxis([50, max(65, min(T_max_real, 80))]);

% 曲线折线图保留网格以供数据读取
subplot(3, 5, 10);
plot(metrics_z, metrics_corr, 'b-', 'LineWidth', 1.5); hold on; 
plot(actual_z_dist_mm, best_corr, 'ro', 'MarkerSize', 10);
grid on; set(gca, 'Color', 'w');

subplot(3, 5, [11 12 13]);
center = round(Nx/2);
plot(x*1e3, imag_target(center, :), 'k--', 'LineWidth', 2); hold on;
plot(x*1e3, p_focal_scaled(center, :)/max(p_focal_scaled(:)), 'r-', 'LineWidth', 1.5);
grid on; set(gca, 'Color', 'w');

subplot(3, 5, [14 15]);
[X_surf, Y_surf] = meshgrid(x*1e3, y*1e3);
surf(X_surf, Y_surf, p_focal_scaled/1e6); shading interp; colormap(gca, jet);
axis off; set(gca, 'Color', 'w');('mm'); zlabel('MPa');


% 15. 输出报告 (Arrhenius 动力学升级版)
fprintf('\n========================================\n');
fprintf('HDSP 严谨物理仿真报告 (最终动力学闭环版)\n');
fprintf('========================================\n');
fprintf('网格配置:\n');
fprintf('  分辨率: %.2f μm\n', dx*1e6);
fprintf('  节点: %.2fM\n', (Nx*Ny*Nz)/1e6);
fprintf('----------------------------------------\n');
fprintf('IASA 全息生成:\n');
fprintf('  最佳截断步数: %d\n', epoch);
fprintf('  相位误差 (连续台阶): %.2f° (最大%.2f°)\n', mean_phase_error*180/pi, max_phase_error*180/pi);
fprintf('----------------------------------------\n');
fprintf('成像质量 (最佳焦面):\n');
fprintf('  位置: %.2f mm\n', actual_z_dist_mm);
fprintf('  Correlation: %.4f\n', best_corr);
fprintf('----------------------------------------\n');
fprintf('严谨物理预测 (空化屏蔽 + Arrhenius 热动力学):\n');
fprintf('  区域中位数定标声压: %.2f MPa\n', target_median_pressure/1e6);
fprintf('  物理空化截断上限: %.2f MPa\n', cavitation_limit/1e6);
fprintf('  照射时间: %.2f 秒\n', exposure_time);
fprintf('  热传导演化最高温度: %.1f°C\n', T_max_real);
% 🚀 [核心修复] 打印全新的热剂量 (Thermal Dose) 阈值，而不是死板的温度！
fprintf('  动力学热剂量阈值 (Omega>=%.1f) 目标覆盖率: %.1f%%\n', Thermal_Dose_Threshold, cured_coverage);
fprintf('  最终热固化形貌交并比 (IoU): %.4f\n', IoU);
fprintf('========================================\n');
reset(gpuDevice); % 强制清空 GPU 显存底层垃圾，确保 k-Wave 每次都能在 15 分钟内跑完！