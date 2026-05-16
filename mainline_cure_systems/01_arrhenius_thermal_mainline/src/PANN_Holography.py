import torch
import torch.nn as nn
import torch.optim as optim
import scipy.io as sio
import numpy as np
import os

# ==========================================
# 0. 绝对路径配置 (专属中转站)
# ==========================================
transport_dir = r"C:\Users\Zh89\Desktop\transport"
input_file = os.path.join(transport_dir, 'target_for_python.mat')
output_file = os.path.join(transport_dir, 'dl_phase_init.mat')

# ==========================================
# 1. 硬件初始化 (强制开启 CUDA)
# ==========================================
device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
print(f"\n🚀 深度学习引擎启动，当前使用设备: {device.type.upper()}")
if device.type == 'cpu':
    print("⚠️ 警告: 未检测到可用 GPU，请检查 PyTorch 的 CUDA 版本！")

if not os.path.exists(input_file):
    raise FileNotFoundError(f"❌ 找不到靶标文件，请检查 MATLAB 是否成功导出到: {input_file}")

# 加载 MATLAB 导出的靶标数据
data = sio.loadmat(input_file)
target_amp = torch.tensor(data['imag_target'], dtype=torch.float32).to(device)
Nx, Ny = int(data['Nx'].item()), int(data['Ny'].item())
Lx = float(data['Lx'].item())
lambda_water = float(data['lambda_water'].item())
z_target = float(data['z_target_dist'].item())

# ==========================================
# 2. 物理角谱传播层 (纯正物理算子)
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
    pad_len = Nx // 2
    padded_field = torch.nn.functional.pad(source_field, (pad_len, pad_len, pad_len, pad_len), mode='constant', value=0)
    
    A_source = torch.fft.fftshift(torch.fft.fft2(torch.fft.ifftshift(padded_field)))
    A_target = A_source * H_forward
    U_target = torch.fft.fftshift(torch.fft.ifft2(torch.fft.ifftshift(A_target)))
    
    return U_target[pad_len:-pad_len, pad_len:-pad_len]

# ==========================================
# 3. 回归巅峰：极简微型 PhaseNet (拒绝参数过载)
# ==========================================
class PhaseNet(nn.Module):
    def __init__(self):
        super().__init__()
        # 仅保留最基础的 3 层卷积，恰到好处的低通滤波先验
        self.net = nn.Sequential(
            nn.Conv2d(1, 16, kernel_size=5, padding=2),
            nn.LeakyReLU(0.2),
            nn.Conv2d(16, 16, kernel_size=5, padding=2),
            nn.LeakyReLU(0.2),
            nn.Conv2d(16, 1, kernel_size=5, padding=2),
            nn.Sigmoid() 
        )
        
    def forward(self, x):
        # 映射到 -pi ~ pi
        return self.net(x) * 2 * np.pi - np.pi

# ==========================================
# 4. 纯粹的物理引导训练 (剔除复杂的正则化)
# ==========================================
model = PhaseNet().to(device)
optimizer = optim.Adam(model.parameters(), lr=0.01)

# 固定输入的纯随机噪声
fixed_noise = torch.randn(1, 1, Nx, Ny).to(device)

epochs = 300  # 回到原汁原味的 300 步
print(f"🧠 开始物理辅助神经网络 (PANN) 炼丹，总步数: {epochs}...")

for epoch in range(epochs):
    optimizer.zero_grad()
    
    # 网络生成极其平滑的相位图
    phase_map = model(fixed_noise).squeeze()
    
    # 构建复数声场
    source_field = 1.0 * torch.exp(1j * phase_map)
    
    # 物理正向传播到焦面
    target_field = propagate_asm(source_field)
    target_amp_pred = torch.abs(target_field)
    
    # 归一化预测振幅
    target_amp_pred_norm = target_amp_pred / (torch.max(target_amp_pred) + 1e-8)
    
    # 最纯粹的物理干涉 MSE 损失
    loss = torch.nn.functional.mse_loss(target_amp_pred_norm, target_amp)
    
    loss.backward()
    optimizer.step()
    
    if (epoch + 1) % 50 == 0:
        print(f"Epoch [{epoch+1}/{epochs}], 物理干涉损失 (MSE): {loss.item():.4f}")

# ==========================================
# 5. 出货给 MATLAB
# ==========================================
final_phase = phase_map.detach().cpu().numpy()
sio.savemat(output_file, {'optimal_initial_phase': final_phase})
print(f"\n✅ 炼丹完成！纯正血统的神级初始相位已投递至中转站: {output_file}")
