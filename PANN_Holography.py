import torch
import torch.nn as nn
import torch.optim as optim
import scipy.io as sio
import numpy as np
import os

# ==========================================
# 0. 绝对路径与硬件配置 (锁死随机种子)
# ==========================================
transport_dir = r"C:\Users\Zh89\Desktop\transport"
input_file = os.path.join(transport_dir, 'target_for_python.mat')
output_file = os.path.join(transport_dir, 'dl_phase_init.mat')

device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
print(f"\n🚀 顶级 PANN 炼丹炉启动，当前设备: {device.type.upper()}")

# 锁定全宇宙的随机种子，确保实验可复现
seed = 42
torch.manual_seed(seed)
torch.cuda.manual_seed(seed)
torch.backends.cudnn.deterministic = True

# 加载靶标数据
if not os.path.exists(input_file):
    raise FileNotFoundError(f"❌ 找不到靶标文件，请检查 MATLAB 导出路径: {input_file}")

data = sio.loadmat(input_file)
target_amp = torch.tensor(data['imag_target'], dtype=torch.float32).to(device)
Nx, Ny = int(data['Nx'].item()), int(data['Ny'].item())
Lx = float(data['Lx'].item())
lambda_water = float(data['lambda_water'].item())
z_target = float(data['z_target_dist'].item())

# ==========================================
# 1. 物理层：角谱传播算子 (ASM)
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
# 2. 损失函数集：相关性 + 像素对齐 + 平滑约束
# ==========================================
def pearson_correlation_loss(output, target):
    """直接优化 MATLAB 的 Correlation 指标"""
    x = output - torch.mean(output)
    y = target - torch.mean(target)
    rho = torch.sum(x * y) / (torch.sqrt(torch.sum(x**2) * torch.sum(y**2)) + 1e-8)
    return 1 - rho 

def tv_loss(img):
    """TV正则化：抑制高频相位突变，消除边缘毛刺"""
    w_variance = torch.sum(torch.pow(img[:,:,:,1:] - img[:,:,:,:-1], 2))
    h_variance = torch.sum(torch.pow(img[:,:,1:,:] - img[:,:,:-1,:], 2))
    return h_variance + w_variance

# ==========================================
# 3. 核心架构：ResNet 残差相位网络 (补全定义)
# ==========================================
class ResBlock(nn.Module):
    def __init__(self, channels):
        super().__init__()
        self.conv = nn.Sequential(
            nn.Conv2d(channels, channels, 3, padding=1),
            nn.BatchNorm2d(channels),
            nn.LeakyReLU(0.2),
            nn.Conv2d(channels, channels, 3, padding=1),
            nn.BatchNorm2d(channels)
        )
    def forward(self, x):
        return x + self.conv(x)

class PhaseResNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.in_conv = nn.Sequential(nn.Conv2d(1, 32, 5, padding=2), nn.LeakyReLU(0.2))
        self.res_blocks = nn.Sequential(ResBlock(32), ResBlock(32), ResBlock(32))
        self.out_conv = nn.Sequential(nn.Conv2d(32, 1, 5, padding=2), nn.Sigmoid())
        
    def forward(self, x):
        x = self.in_conv(x)
        x = self.res_blocks(x)
        return self.out_conv(x) * 2 * np.pi - np.pi

# ==========================================
# 4. 训练引擎 (2000 Epochs + 余弦退火学习率)
# ==========================================
model = PhaseResNet().to(device)
optimizer = optim.Adam(model.parameters(), lr=0.01)
scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=2000, eta_min=1e-5)

# 固定输入的纯随机噪声
fixed_noise = torch.randn(1, 1, Nx, Ny).to(device)

print(f"🧠 PANN 正在进行【声场纯净度】攻坚，预计 2000 步...")

for epoch in range(2000):
    optimizer.zero_grad()
    
    phase_map = model(fixed_noise).squeeze()
    source_field = torch.exp(1j * phase_map)
    
    # 物理正向传播
    target_field = propagate_asm(source_field)
    pred_amp = torch.abs(target_field)
    pred_amp_norm = pred_amp / (torch.max(pred_amp) + 1e-8)
    
    # --- 组合损失函数 ---
    loss_corr = pearson_correlation_loss(pred_amp_norm, target_amp)
    loss_mse = torch.nn.functional.mse_loss(pred_amp_norm, target_amp)
    loss_tv = tv_loss(phase_map.unsqueeze(0).unsqueeze(0)) 
    
    # 核心策略：70% 权重交给相关性优化
    total_loss = 0.7 * loss_corr + 0.2 * loss_mse + 0.05 * loss_tv
    
    total_loss.backward()
    optimizer.step()
    scheduler.step()
    
    if (epoch + 1) % 200 == 0:
        current_corr = 1 - loss_corr.item()
        print(f"Epoch [{epoch+1}/2000] | Corr: {current_corr:.4f} | TV: {loss_tv.item():.2f} | LR: {optimizer.param_groups[0]['lr']:.6f}")

# ==========================================
# 5. 导出结果给 MATLAB
# ==========================================
final_phase = phase_map.detach().cpu().numpy()
sio.savemat(output_file, {'optimal_initial_phase': final_phase})
print(f"\n✅ 炼丹完成！极致平滑相位已投递至: {output_file}")