import torch
import torch.nn as nn
import torch.optim as optim
import scipy.io as sio
import numpy as np
import os

# ==========================================
# 0. 基础配置 (保持路径与种子锁定)
# ==========================================
transport_dir = r"C:\Users\Zh89\Desktop\transport"
input_file = os.path.join(transport_dir, 'target_for_python.mat')
output_file = os.path.join(transport_dir, 'dl_phase_init.mat')

device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
seed = 42 # 锁定种子，确保调参有效
torch.manual_seed(seed)
torch.cuda.manual_seed(seed)

# 加载数据 (逻辑同前...)
data = sio.loadmat(input_file)
target_amp = torch.tensor(data['imag_target'], dtype=torch.float32).to(device)
Nx, Ny = int(data['Nx'].item()), int(data['Ny'].item())

# ==========================================
# 1. 核心损失函数：Pearson Correlation Loss
# ==========================================
def pearson_correlation_loss(output, target):
    """直接针对 MATLAB 的 Correlation 指标进行优化"""
    x = output - torch.mean(output)
    y = target - torch.mean(target)
    rho = torch.sum(x * y) / (torch.sqrt(torch.sum(x**2) * torch.sum(y**2)) + 1e-8)
    return 1 - rho # 1 - 相关系数，越小代表相关性越高

def tv_loss(img):
    """抑制高频散斑，消除“左脚锯齿”"""
    w_variance = torch.sum(torch.pow(img[:,:,:,1:] - img[:,:,:,:-1], 2))
    h_variance = torch.sum(torch.pow(img[:,:,1:,:] - img[:,:,:-1,:], 2))
    return h_variance + w_variance

# ==========================================
# 2. 训练引擎 (ResNet + 混合 Loss)
# ==========================================
# [此处保留你之前的 ResNet 架构代码...]

model = PhaseResNet().to(device)
optimizer = optim.Adam(model.parameters(), lr=0.01)
scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=2000)

fixed_noise = torch.randn(1, 1, Nx, Ny).to(device)

print(f"🧠 PANN 正在进行【声场纯净度】攻坚，目标 Correlation > 0.76...")

for epoch in range(2000):
    optimizer.zero_grad()
    
    phase_map = model(fixed_noise).squeeze()
    source_field = torch.exp(1j * phase_map)
    
    # 物理传播 (propagate_asm 逻辑同前)
    target_field = propagate_asm(source_field)
    pred_amp = torch.abs(target_field)
    pred_amp_norm = pred_amp / (torch.max(pred_amp) + 1e-8)
    
    # --- 混合 Loss 策略 ---
    loss_corr = pearson_correlation_loss(pred_amp_norm, target_amp)
    loss_mse = torch.nn.functional.mse_loss(pred_amp_norm, target_amp)
    loss_tv = tv_loss(phase_map.unsqueeze(0).unsqueeze(0)) 
    
    # 权重分配：前期靠 MSE 定位，后期靠 Corr 冲分，TV 始终压制毛刺
    total_loss = 0.7 * loss_corr + 0.2 * loss_mse + 0.05 * loss_tv
    
    total_loss.backward()
    optimizer.step()
    scheduler.step()
    
    if (epoch + 1) % 200 == 0:
        actual_corr = 1 - loss_corr.item()
        print(f"Epoch [{epoch+1}/2000] | Corr: {actual_corr:.4f} | TV: {loss_tv.item():.2f}")

# 导出结果...