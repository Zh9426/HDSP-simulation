import math  # 导入数学库，用于常数和数学函数
import os  # 导入操作系统库，用于文件路径操作

import numpy as np  # 导入NumPy库，用于高效的数值计算
import scipy.io as sio  # 导入SciPy的I/O库，用于加载和保存.mat文件
import scipy.ndimage  # 导入SciPy的ndimage库，用于图像处理，如高斯滤波
import torch  # 导入PyTorch库，用于深度学习和张量计算
import torch.nn.functional as F  # 导入PyTorch的函数库，如卷积、padding等
import torch.optim as optim  # 导入PyTorch的优化器库，如Adam

TWO_PI = 2.0 * math.pi  # 定义常量 2π，用于相位计算


# 定义一个函数，使用PyTorch对2D图像进行高斯模糊
def gaussian_blur2d(image_2d, sigma_px):
    if sigma_px <= 0.05:  # 如果模糊半径过小，直接返回原图以提高效率
        return image_2d

    radius = max(1, int(math.ceil(3.0 * sigma_px)))  # 根据sigma计算模糊核的半径 (3-sigma原则)
    coords = torch.arange(-radius, radius + 1, device=image_2d.device, dtype=image_2d.dtype)  # 创建一维坐标
    kernel_1d = torch.exp(-(coords**2) / (2.0 * sigma_px**2))  # 计算一维高斯核
    kernel_1d = kernel_1d / torch.sum(kernel_1d)  # 归一化一维高斯核
    kernel_2d = torch.outer(kernel_1d, kernel_1d)  # 通过外积从一维核生成二维高斯核
    kernel_2d = kernel_2d / torch.sum(kernel_2d)  # 归一化二维高斯核
    kernel_4d = kernel_2d.unsqueeze(0).unsqueeze(0)  # 扩展核的维度以适应PyTorch的卷积输入 (B, C_in, H, W)

    image_4d = image_2d.unsqueeze(0).unsqueeze(0)  # 扩展图像的维度以适应PyTorch的卷积输入
    padding = radius  # 设置padding大小，以保持图像尺寸不变
    blurred = F.conv2d(image_4d, kernel_4d, padding=padding)  # 执行二维卷积操作
    return blurred.squeeze(0).squeeze(0)  # 移除多余的维度，返回二维图像


# 定义一个函数，将场（如振幅、能量）归一化到[0, 1]范围
def normalize_map(field):
    return field / (torch.max(field) + 1e-8)  # 加上一个很小的数(epsilon)防止除以零


# 定义皮尔逊相关系数损失函数。用于衡量两个图像的线性相关性
def pearson_correlation_loss(output, target):
    x = output - torch.mean(output)  # 减去均值
    y = target - torch.mean(target)  # 减去均值
    rho = torch.sum(x * y) / (torch.sqrt(torch.sum(x**2) * torch.sum(y**2)) + 1e-8)  # 计算皮尔逊相关系数
    return 1.0 - rho  # 返回 1 - rho，因为优化器是最小化损失，而我们希望最大化相关性


# 定义相位量化函数，使用直通估计器(Straight-Through Estimator, STE)
def quantize_phase_ste(phase_map, phase_bias, phase_step, min_base_layers):
    wrapped_phase = torch.remainder(phase_map + phase_bias, TWO_PI)  # 将相位包裹到 [0, 2π) 区间
    layer_continuous = wrapped_phase / phase_step + min_base_layers  # 计算连续的层级值
    layer_hard = torch.round(layer_continuous)  # 对层级进行四舍五入，得到离散的层级
    phase_hard = torch.remainder(layer_hard * phase_step, TWO_PI)  # 从离散层级计算量化后的相位
    # STE: 前向传播使用硬量化结果，反向传播时梯度直接通过，忽略round操作的不可导问题
    phase_quantized = wrapped_phase + (phase_hard - wrapped_phase).detach()
    return phase_quantized, layer_continuous  # 返回量化相位和连续层级值


# 使用Floyd-Steinberg误差扩散算法对连续层级图进行抖动量化
def error_diffusion_quantize_layers(layer_continuous, mask, min_base_layers, max_layer_index):
    work = layer_continuous.astype(np.float64).copy()  # 创建一个可修改的副本
    layer_map = np.full_like(work, min_base_layers, dtype=np.int32)  # 初始化最终的层级图

    rows, cols = work.shape  # 获取图像尺寸
    for row in range(rows):  # 逐行扫描
        if row % 2 == 0:  # 偶数行，从左到右
            col_iter = range(cols)
            # 定义误差扩散的邻居和权重 (Floyd-Steinberg)
            neighbors = ((0, 1, 7.0 / 16.0), (1, -1, 3.0 / 16.0), (1, 0, 5.0 / 16.0), (1, 1, 1.0 / 16.0))
        else:  # 奇数行，从右到左（蛇形扫描，减少伪影）
            col_iter = range(cols - 1, -1, -1)
            neighbors = ((0, -1, 7.0 / 16.0), (1, 1, 3.0 / 16.0), (1, 0, 5.0 / 16.0), (1, -1, 1.0 / 16.0))

        for col in col_iter:  # 逐列处理
            if mask[row, col] < 0.5:  # 只处理有效区域（掩码内）的像素
                continue

            # 对当前像素值进行裁剪和四舍五入，得到量化值
            quantized_val = int(np.clip(np.round(work[row, col]), min_base_layers, max_layer_index))
            layer_map[row, col] = quantized_val  # 存入最终的层级图
            quant_error = work[row, col] - quantized_val  # 计算量化误差

            # 将量化误差按权重扩散到邻近的像素
            for d_row, d_col, weight in neighbors:
                n_row, n_col = row + d_row, col + d_col
                # 检查邻居像素是否在图像范围内且在掩码内
                if 0 <= n_row < rows and 0 <= n_col < cols and mask[n_row, n_col] > 0.5:
                    work[n_row, n_col] += quant_error * weight

    return layer_map  # 返回抖动量化后的层级图


# 0. 物理配置
# ==========================================
transport_dir = r"C:\Users\Zh89\Desktop\transport"  # 定义数据中转文件夹路径
input_file = os.path.join(transport_dir, "target_for_python.mat")  # 定义输入.mat文件的完整路径
output_file = os.path.join(transport_dir, "dl_phase_init.mat")  # 定义输出.mat文件的完整路径

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")  # 检查是否有可用的CUDA GPU，否则使用CPU
print("\n[INFO] PANN-Thermal-Holo 启动：量化感知 + 热剂量主导损失 + 空间抖动初始化")  # 打印启动信息

if not os.path.exists(input_file):  # 检查输入文件是否存在
    raise FileNotFoundError(f"找不到中转数据: {input_file}")  # 如果不存在，则抛出异常

data = sio.loadmat(input_file)  # 使用scipy.io加载.mat文件
# 确定用于设计的靶点振幅图的键名，优先使用 "imag_target_design"
design_key = "imag_target_design" if "imag_target_design" in data else "imag_target"
target_amp = torch.tensor(data[design_key], dtype=torch.float32, device=device)  # 加载设计目标振幅，并转换为PyTorch张量
target_amp_raw = torch.tensor(data["imag_target"], dtype=torch.float32, device=device)  # 加载原始目标振幅

# 从.mat文件中加载各种物理和模拟参数
Nx, Ny = int(data["Nx"].item()), int(data["Ny"].item())  # 换能器阵列的像素数
Lx = float(data["Lx"].item())  # 换能器阵列的物理尺寸 (米)
lambda_water = float(data["lambda_water"].item())  # 声波在水中的波长 (米)
z_target = float(data["z_target_dist"].item())  # 目标平面距离 (米)
dz = float(data["dz"].item())  # 打印介质的厚度 (米)
f0 = float(data["f0"].item())  # 超声频率 (赫兹)
c_water = float(data["c_water"].item())  # 水中的声速 (米/秒)
c_board = float(data["c_board"].item())  # 打印介质中的声速 (米/秒)
thermal_sigma_px = float(data["thermal_sigma_px"].item()) if "thermal_sigma_px" in data else 1.0  # 热扩散的sigma值（像素单位），如果不存在则默认为1.0
min_base_layers = int(data["min_base_layers"].item()) if "min_base_layers" in data else 2  # 最小基底层数，如果不存在则默认为2

# 1. 热预补偿目标与物理低通
# ==========================================
resolution_limit_mm = 0.61 * lambda_water * 1000.0  # 计算瑞利衍射极限 (毫米)
sigma_mm = resolution_limit_mm * 0.35  # 估算点扩散函数(PSF)的sigma (毫米)
sigma_px = sigma_mm / (Lx / Nx * 1000.0)  # 将sigma从毫米转换为像素单位

target_np = target_amp.detach().cpu().numpy().squeeze()  # 将目标振幅转为NumPy数组
target_smooth_np = scipy.ndimage.gaussian_filter(target_np, sigma_px)  # 对目标进行高斯滤波，模拟物理低通效应
target_smooth = torch.tensor(target_smooth_np, dtype=torch.float32, device=device)  # 转回PyTorch张量
target_smooth = normalize_map(target_smooth)  # 归一化平滑后的目标

target_raw_np = target_amp_raw.detach().cpu().numpy().squeeze()  # 将原始目标振幅转为NumPy数组
line_target_np = (target_raw_np > 0.45).astype(np.float32)  # 通过阈值处理生成二值化的线状目标
halo_target_np = scipy.ndimage.gaussian_filter(line_target_np, max(1.0, thermal_sigma_px)) > 0.08  # 模拟热扩散生成一个更宽的区域(潜在光晕区)
halo_ring_np = np.logical_and(halo_target_np, line_target_np < 0.5).astype(np.float32)  # 定义光晕环区域（在扩散区内但不在原始目标线上）
far_dark_np = np.logical_not(halo_target_np).astype(np.float32)  # 定义远离目标的暗场区域

target_binary = torch.tensor(line_target_np, dtype=torch.float32, device=device)  # 二值化目标
halo_mask = torch.tensor(halo_ring_np, dtype=torch.float32, device=device)  # 光晕环掩码
far_dark_mask = torch.tensor(far_dark_np, dtype=torch.float32, device=device)  # 暗场掩码
target_dose_np = scipy.ndimage.gaussian_filter(line_target_np, max(0.8, thermal_sigma_px))  # 模拟热剂量分布（比声能分布更模糊）
target_dose = torch.tensor(target_dose_np, dtype=torch.float32, device=device)  # 将目标热剂量转为张量
# 结合平滑的声学目标和热剂量目标，创建一个混合目标，防止剂量目标过低
target_dose = normalize_map(torch.maximum(target_dose, 0.35 * target_smooth))
target_raw_norm = normalize_map(target_amp_raw)  # 归一化原始目标振幅

# 2. 物理传播算子 (ASM)
# ==========================================
pad_factor = 2  # 定义padding因子，用于避免角谱法(ASM)中的卷绕误差
Nx_pad, Ny_pad = Nx * pad_factor, Ny * pad_factor  # 计算padding后的尺寸
dk = 2.0 * math.pi / (Lx * pad_factor)  # 计算频率域的采样间隔
kx = torch.arange(-Nx_pad / 2, Nx_pad / 2, device=device) * dk  # 创建x方向的频率坐标
ky = torch.arange(-Ny_pad / 2, Ny_pad / 2, device=device) * dk  # 创建y方向的频率坐标
Kx, Ky = torch.meshgrid(kx, ky, indexing="ij")  # 创建2D频率网格
Kz_sq = (2.0 * math.pi / lambda_water) ** 2 - Kx**2 - Ky**2  # 计算Kz的平方，基于波动方程 k^2 = kx^2 + ky^2 + kz^2
Kz_sq = torch.clamp(Kz_sq, min=0.0)  # 将Kz的平方中小于0的值（倏逝波）截断为0
H_forward = torch.exp(1j * torch.sqrt(Kz_sq) * z_target)  # 计算角谱法的传递函数 H = exp(i * kz * z)


# 定义使用角谱法(ASM)进行波前传播的函数
def propagate_asm(source_field):
    pad_len_x, pad_len_y = Nx // 2, Ny // 2  # 计算单边的padding长度
    # 对源场进行零填充
    padded_field = F.pad(source_field, (pad_len_y, pad_len_y, pad_len_x, pad_len_x), mode="constant", value=0)
    spectrum = torch.fft.fftshift(torch.fft.fft2(torch.fft.ifftshift(padded_field)))  # 傅里叶变换到频域
    propagated = torch.fft.fftshift(torch.fft.ifft2(torch.fft.ifftshift(spectrum * H_forward)))  # 乘以传递函数并傅里叶逆变换回空间域
    return propagated[pad_len_x:-pad_len_x, pad_len_y:-pad_len_y]  # 裁剪掉padding区域，返回结果


# 3. 量化感知优化
# ==========================================
k_diff = abs(2.0 * math.pi * f0 / c_water - 2.0 * math.pi * f0 / c_board)  # 计算两种介质中的波数差 k = 2πf/c
phase_step = k_diff * dz  # 计算每个打印层级对应的相位变化量
max_layer_index = min_base_layers + int(math.ceil(TWO_PI / phase_step)) + 1  # 计算覆盖2π相位所需的最大层级索引

x_vec = torch.linspace(-Lx / 2, Lx / 2, Nx, device=device)  # 创建x方向的空间坐标
y_vec = torch.linspace(-Lx / 2, Lx / 2, Ny, device=device)  # 创建y方向的空间坐标
Y_grid, X_grid = torch.meshgrid(y_vec, x_vec, indexing="ij")  # 创建2D空间坐标网格
source_mask = ((X_grid**2 + Y_grid**2) <= (32e-3) ** 2).float()  # 创建一个圆形掩码，模拟直径为64mm的圆形换能器

dark_weight = 1.0 + 8.0 * halo_mask + 12.0 * far_dark_mask  # 定义暗区的权重图，对光晕区和远暗区施加更高的惩罚
edge_weight = 1.0 + 2.5 * torch.abs(target_smooth - gaussian_blur2d(target_smooth, 1.0))  # 定义边缘权重图，加强对目标边缘细节的关注
weight_map = dark_weight * edge_weight  # 组合成最终的权重图，用于加权MSE损失

initial_phase = (torch.rand(Nx, Ny, device=device) * TWO_PI) - math.pi  # 随机初始化相位图，范围在[-π, π]
phase_map = torch.nn.Parameter(initial_phase)  # 将相位图封装为可训练的参数
phase_bias = torch.nn.Parameter(torch.zeros(1, device=device))  # 定义一个全局相位偏置，也是可训练参数

optimizer = optim.Adam([phase_map, phase_bias], lr=0.06)  # 使用Adam优化器，学习率为0.06
scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=2500, eta_min=0.003)  # 使用余弦退火学习率调度器
epochs = 5000  # 设置总的训练轮数

best_loss = float("inf")  # 初始化最佳损失为无穷大
best_state = None  # 初始化用于保存最佳状态的变量

for epoch in range(epochs):  # 开始优化循环
    optimizer.zero_grad()  # 清除上一轮的梯度

    # 通过量化函数得到量化后的相位和连续层级值
    phase_quantized, layer_continuous = quantize_phase_ste(phase_map, phase_bias, phase_step, min_base_layers)
    source_field = torch.exp(1j * phase_quantized) * source_mask  # 计算源平面场分布（复振幅）
    target_field = propagate_asm(source_field)  # 将源场传播到目标平面

    pred_amp = torch.abs(target_field)  # 计算目标平面的振幅分布
    pred_energy = normalize_map(pred_amp**2)  # 计算并归一化能量分布（振幅的平方）
    pred_dose = normalize_map(gaussian_blur2d(pred_energy, thermal_sigma_px))  # 模拟热扩散，得到预测的热剂量分布

    # --- 计算各项损失函数 ---
    loss_dose_corr = pearson_correlation_loss(pred_dose, target_dose)  # 1. 预测剂量与目标剂量的相关性损失
    loss_dose_wmse = torch.mean(weight_map * (pred_dose - target_dose) ** 2)  # 2. 预测剂量与目标剂量的加权均方误差

    inside_vals = pred_dose[target_binary > 0.5]  # 提取目标区域内的剂量值
    loss_uniformity = torch.var(inside_vals) if inside_vals.numel() > 4 else torch.tensor(0.0, device=device)  # 3. 目标区域内的均匀性损失（方差）

    halo_vals = pred_dose[halo_mask > 0.5]  # 提取光晕区域的剂量值
    loss_halo = torch.mean(halo_vals**2) if halo_vals.numel() > 4 else torch.tensor(0.0, device=device)  # 4. 光晕抑制损失
    dark_vals = pred_dose[far_dark_mask > 0.5]  # 提取远暗区的剂量值
    loss_dark = torch.mean(dark_vals**2)  # 5. 暗场抑制损失

    current_ee = torch.sum(pred_energy * target_binary) / (torch.sum(pred_energy) + 1e-8)  # 计算能量效率（落入目标区的能量比例）
    loss_ee = 1.0 - current_ee  # 6. 能量效率损失

    raw_mismatch = torch.mean((normalize_map(pred_amp) - target_raw_norm) ** 2)  # 7. 预测振幅与原始目标振幅的MSE，作为辅助
    loss_layer_margin = torch.mean((layer_continuous - torch.round(layer_continuous)) ** 2)  # 8. 层级边缘损失，鼓励连续层级值接近整数

    # 将所有损失函数加权求和，得到总损失
    total_loss = (
        1.4 * loss_dose_corr
        + 2.8 * loss_dose_wmse
        + 4.0 * loss_uniformity
        + 4.0 * loss_halo
        + 5.0 * loss_dark
        + 2.0 * loss_ee
        + 0.6 * raw_mismatch
        + 0.15 * loss_layer_margin
    )

    total_loss.backward()  # 反向传播，计算梯度
    optimizer.step()  # 更新模型参数（相位图和偏置）
    scheduler.step()  # 更新学习率

    with torch.no_grad():  # 在不计算梯度的上下文中
        phase_bias[:] = torch.remainder(phase_bias, TWO_PI)  # 将相位偏置包裹到[0, 2π)

    if total_loss.item() < best_loss:  # 如果当前损失优于历史最佳损失
        best_loss = total_loss.item()  # 更新最佳损失
        best_state = {  # 保存当前模型的状态（相位图和偏置）
            "phase_map": phase_map.detach().clone(),
            "phase_bias": phase_bias.detach().clone(),
        }

    if (epoch + 1) % 100 == 0:  # 每100轮打印一次训练信息
        print(
            f"Epoch [{epoch + 1}/{epochs}] | DoseCorr: {1.0 - loss_dose_corr.item():.4f} "
            f"| EE: {current_ee.item() * 100:.2f}% | Halo: {loss_halo.item():.4f} "
            f"| Dark: {loss_dark.item():.4f} | Loss: {total_loss.item():.4f}"
        )

# 4. 以量化感知结果做空间抖动输出
# ==========================================
phase_map_final = best_state["phase_map"]  # 获取优化得到的最佳相位图
phase_bias_final = best_state["phase_bias"]  # 获取最佳相位偏置
wrapped_phase = torch.remainder(phase_map_final + phase_bias_final, TWO_PI)  # 计算最终的包裹相位
# 将最终的连续相位图转换为连续层级图，并转到CPU和NumPy格式
layer_continuous = (wrapped_phase / phase_step + min_base_layers).detach().cpu().numpy()
mask_np = source_mask.detach().cpu().numpy()  # 将源掩码转为NumPy格式

# 使用误差扩散算法对连续层级图进行最终的硬量化和抖动处理
dithered_layers = error_diffusion_quantize_layers(layer_continuous, mask_np, min_base_layers, max_layer_index)
dithered_phase = np.mod(dithered_layers * phase_step, TWO_PI).astype(np.float32)  # 从抖动后的层级图计算最终的离散相位
dithered_phase *= mask_np.astype(np.float32)  # 应用掩码，确保换能器外的相位为0

sio.savemat(  # 使用scipy.io将多个结果变量保存到.mat文件中
    output_file,
    {
        "optimal_initial_phase": dithered_phase,  # 最终的、抖动量化后的相位图
        "optimal_phase_bias": np.array([[phase_bias_final.item()]], dtype=np.float32),  # 最终的相位偏置
        "optimal_layer_map": dithered_layers.astype(np.float32),  # 最终的、抖动量化后的层级图
        "phase_step": np.array([[phase_step]], dtype=np.float32),  # 每个层级对应的相位步进
        "target_dose_design": target_dose.detach().cpu().numpy().astype(np.float32),  # 用于优化的目标热剂量图
        "line_target_mask": target_binary.detach().cpu().numpy().astype(np.float32),  # 目标线掩码
        "halo_target_mask": halo_mask.detach().cpu().numpy().astype(np.float32),  # 光晕环掩码
    },
)

print(f"\n[OK] 相位初始化已写入: {output_file}")  # 打印完成信息
