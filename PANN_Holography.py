import torch
import torch.optim as optim
import scipy.io as sio
import numpy as np
import os
import scipy.ndimage

# ==========================================
# 0. 顶级物理配置 (OD=64mm, f=4.5MHz)
# ==========================================
transport_dir = r"C:\Users\Zh89\Desktop\transport"
input_file = os.path.join(transport_dir, 'target_for_python.mat')
output_file = os.path.join(transport_dir, 'dl_phase_init.mat')

device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
print(f"\n🚀 GD-Holo v3.0 启动 [引入自适应非对称损失，修复噪点与线条扭曲]")

if not os.path.exists(input_file): raise FileNotFoundError(f"❌ 找不到靶标: {input_file}")

data = sio.loadmat(input_file)
target_amp = torch.tensor(data['imag_target'], dtype=torch.float32).to(device)
Nx, Ny = int(data['Nx'].item()), int(data['Ny'].item())
Lx = float(data['Lx'].item())
lambda_water = float(data['lambda_water'].item())
z_target = float(data['z_target_dist'].item())

# ==========================================
# 1. 物理低通滤波 (轻微消除数字锯齿)
# ==========================================
resolution_limit_mm = 0.61 * lambda_water * 1000 
sigma_mm = resolution_limit_mm * 0.35 
sigma_px = sigma_mm / (Lx/Nx * 1000)

temp_target = target_amp.cpu().numpy().squeeze()
temp_target_smooth = scipy.ndimage.gaussian_filter(temp_target, sigma_px)
target_amp_phys = torch.tensor(temp_target_smooth, dtype=torch.float32).to(device)
target_amp_phys = target_amp_phys / (torch.max(target_amp_phys) + 1e-8)

# ==========================================
# 2. 物理传播算子 (ASM)
# ==========================================
pad_factor = 2
Nx_pad, Ny_pad = Nx * pad_factor, Ny * pad_factor
dk = 2 * np.pi / (Lx * pad_factor)
kx = torch.arange(-Nx_pad/2, Nx_pad/2) * dk
ky = torch.arange(-Ny_pad/2, Ny_pad/2) * dk
Kx, Ky = torch.meshgrid(kx, ky, indexing='ij')
Kx, Ky = Kx.to(device), Ky.to(device)
Kz_sq = (2 * np.pi / lambda_water)**2 - Kx**2 - Ky**2
Kz_sq[Kz_sq < 0] = 0
H_forward = torch.exp(1j * torch.sqrt(Kz_sq) * z_target)

def propagate_asm(source_field):
    pad_len_x, pad_len_y = Nx // 2, Ny // 2
    padded_field = torch.nn.functional.pad(source_field, (pad_len_y, pad_len_y, pad_len_x, pad_len_x), mode='constant', value=0)
    A_source = torch.fft.fftshift(torch.fft.fft2(torch.fft.ifftshift(padded_field)))
    U_target = torch.fft.fftshift(torch.fft.ifft2(torch.fft.ifftshift(A_source * H_forward)))
    return U_target[pad_len_x:-pad_len_x, pad_len_y:-pad_len_y]

def pearson_correlation_loss(output, target):
    x = output - torch.mean(output); y = target - torch.mean(target)
    rho = torch.sum(x * y) / (torch.sqrt(torch.sum(x**2) * torch.sum(y**2)) + 1e-8)
    return 1 - rho 

def tv_loss(img):
    h_variance = torch.sum(torch.pow(img[1:, :] - img[:-1, :], 2))
    w_variance = torch.sum(torch.pow(img[:, 1:] - img[:, :-1], 2))
    return (h_variance + w_variance) / (Nx * Ny)

# ==========================================
# 3. 極速純物理梯度下降 (自适应优化)
# ==========================================
phase_map = torch.nn.Parameter((torch.rand(Nx, Ny, device=device) * 2 * np.pi) - np.pi)

optimizer = optim.Adam([phase_map], lr=0.1)
scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=1000, eta_min=0.001)

# 🌟 构建通用权重掩膜 (自动识别任何图案的背景)
# 靶标亮度 < 0.2 的地方被定义为背景(孔洞)
bg_mask = (target_amp_phys < 0.2).float()
weight_map = torch.ones_like(target_amp_phys)
# 对背景孔洞施加 8 倍的极端惩罚，绞杀孤立块状物！
weight_map[bg_mask == 1] = 8.0 

epochs = 1000
print(f"🧠 开始执行自适应非对称全息优化 (彻底斩除空洞噪点)...")

for epoch in range(epochs):
    optimizer.zero_grad()
    
    source_field = torch.exp(1j * phase_map)
    target_field = propagate_asm(source_field)
    pred_amp = torch.abs(target_field)
    pred_amp_norm = pred_amp / (torch.max(pred_amp) + 1e-8)
    
    # 1. 相关性约束 (保大局)
    loss_corr = pearson_correlation_loss(pred_amp_norm, target_amp_phys)
    
    # 2. 🌟 自适应加权 MSE (防过热/防空洞散斑)
    error = pred_amp_norm - target_amp_phys
    loss_wmse = torch.mean(weight_map * (error ** 2))
    
    # 3. 🌟 局部 TV 惩罚 (保直线)
    # 仅对背景区域应用 TV 平滑，不干扰主体边缘，保持横平竖直
    pred_bg_only = pred_amp_norm * bg_mask
    loss_tv_bg = tv_loss(pred_bg_only)
    
    # 组合重拳
    total_loss = 1.0 * loss_corr + 1.0 * loss_wmse + 0.1 * loss_tv_bg
    
    total_loss.backward()
    optimizer.step()
    scheduler.step()
    
    if (epoch + 1) % 100 == 0:
        actual_corr = 1 - loss_corr.item()
        print(f"Epoch [{epoch+1}/{epochs}] | Corr: {actual_corr:.4f} | wMSE: {loss_wmse.item():.4f} | Loss: {total_loss.item():.4f}")

# ==========================================
# 4. 导出数据
# ==========================================
final_phase = phase_map.detach().cpu().numpy()
sio.savemat(output_file, {'optimal_initial_phase': final_phase})
print(f"\n✅ 极致纯净 GD-Holo 相位已备好，投递至: {output_file}")