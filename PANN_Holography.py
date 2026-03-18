import torch
import torch.nn as nn
import torch.optim as optim
import scipy.io as sio
import numpy as np
import os

# ==========================================
# 0. 路径与硬件 (锁死天命种子)
# ==========================================
transport_dir = r"C:\Users\Zh89\Desktop\transport"
input_file = os.path.join(transport_dir, 'target_for_python.mat')
output_file = os.path.join(transport_dir, 'dl_phase_init.mat')

device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
print(f"\n🚀 极简巅峰版 PANN 启动，当前设备: {device.type.upper()}")

seed = 42  # 锁死随机种子，拒绝抽卡
torch.manual_seed(seed)
torch.cuda.manual_seed(seed)
torch.backends.cudnn.deterministic = True

data = sio.loadmat(input_file)
target_amp = torch.tensor(data['imag_target'], dtype=torch.float32).to(device)
Nx, Ny = int(data['Nx'].item()), int(data['Ny'].item())
Lx = float(data['Lx'].item())
lambda_water = float(data['lambda_water'].item())
z_target = float(data['z_target_dist'].item())

# ==========================================
# 1. 物理层
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
# 2. 核心：回归极简 3 层微型网络
# ==========================================
class PhaseNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv2d(1, 16, kernel_size=5, padding=2),
            nn.LeakyReLU(0.2),
            nn.Conv2d(16, 16, kernel_size=5, padding=2),
            nn.LeakyReLU(0.2),
            nn.Conv2d(16, 1, kernel_size=5, padding=2),
            nn.Sigmoid() 
        )
        
    def forward(self, x):
        return self.net(x) * 2 * np.pi - np.pi

# ==========================================
# 3. 极速训练 (仅 300 步，纯 MSE)
# ==========================================
model = PhaseNet().to(device)
optimizer = optim.Adam(model.parameters(), lr=0.01)
fixed_noise = torch.randn(1, 1, Nx, Ny).to(device)

epochs = 300
print(f"🧠 开始物理辅助炼丹，总步数: {epochs}...")

for epoch in range(epochs):
    optimizer.zero_grad()
    phase_map = model(fixed_noise).squeeze()
    source_field = 1.0 * torch.exp(1j * phase_map)
    
    target_field = propagate_asm(source_field)
    target_amp_pred = torch.abs(target_field)
    target_amp_pred_norm = target_amp_pred / (torch.max(target_amp_pred) + 1e-8)
    
    loss = torch.nn.functional.mse_loss(target_amp_pred_norm, target_amp)
    
    loss.backward()
    optimizer.step()
    
    if (epoch + 1) % 50 == 0:
        print(f"Epoch [{epoch+1}/{epochs}], MSE Loss: {loss.item():.4f}")

final_phase = phase_map.detach().cpu().numpy()
sio.savemat(output_file, {'optimal_initial_phase': final_phase})
print(f"\n✅ 极简神级相位已备好，投递至: {output_file}")