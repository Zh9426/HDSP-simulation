
import math
import os

import numpy as np
import scipy.io as sio
import scipy.ndimage
import torch
import torch.nn.functional as F
import torch.optim as optim

TWO_PI = 2.0 * math.pi


def gaussian_blur2d(image_2d, sigma_px):
    if sigma_px <= 0.05:
        return image_2d

    radius = max(1, int(math.ceil(3.0 * sigma_px)))
    coords = torch.arange(-radius, radius + 1, device=image_2d.device, dtype=image_2d.dtype)
    kernel_1d = torch.exp(-(coords**2) / (2.0 * sigma_px**2))
    kernel_1d = kernel_1d / torch.sum(kernel_1d)
    kernel_2d = torch.outer(kernel_1d, kernel_1d)
    kernel_2d = kernel_2d / torch.sum(kernel_2d)
    kernel_4d = kernel_2d.unsqueeze(0).unsqueeze(0)

    image_4d = image_2d.unsqueeze(0).unsqueeze(0)
    padding = radius
    blurred = F.conv2d(image_4d, kernel_4d, padding=padding)
    return blurred.squeeze(0).squeeze(0)


def normalize_map(field):
    return field / (torch.max(field) + 1e-8)


def pearson_correlation_loss(output, target):
    x = output - torch.mean(output)
    y = target - torch.mean(target)
    rho = torch.sum(x * y) / (torch.sqrt(torch.sum(x**2) * torch.sum(y**2)) + 1e-8)
    return 1.0 - rho


def quantize_phase_ste(phase_map, phase_bias, phase_step, min_base_layers):
    wrapped_phase = torch.remainder(phase_map + phase_bias, TWO_PI)
    layer_continuous = wrapped_phase / phase_step + min_base_layers
    layer_hard = torch.round(layer_continuous)
    phase_hard = torch.remainder(layer_hard * phase_step, TWO_PI)
    phase_quantized = wrapped_phase + (phase_hard - wrapped_phase).detach()
    return phase_quantized, layer_continuous


def error_diffusion_quantize_layers(layer_continuous, mask, min_base_layers, max_layer_index):
    work = layer_continuous.astype(np.float64).copy()
    layer_map = np.full_like(work, min_base_layers, dtype=np.int32)

    rows, cols = work.shape
    for row in range(rows):
        if row % 2 == 0:
            col_iter = range(cols)
            neighbors = ((0, 1, 7.0 / 16.0), (1, -1, 3.0 / 16.0), (1, 0, 5.0 / 16.0), (1, 1, 1.0 / 16.0))
        else:
            col_iter = range(cols - 1, -1, -1)
            neighbors = ((0, -1, 7.0 / 16.0), (1, 1, 3.0 / 16.0), (1, 0, 5.0 / 16.0), (1, -1, 1.0 / 16.0))

        for col in col_iter:
            if mask[row, col] < 0.5:
                continue

            quantized_val = int(np.clip(np.round(work[row, col]), min_base_layers, max_layer_index))
            layer_map[row, col] = quantized_val
            quant_error = work[row, col] - quantized_val

            for d_row, d_col, weight in neighbors:
                n_row = row + d_row
                n_col = col + d_col
                if 0 <= n_row < rows and 0 <= n_col < cols and mask[n_row, n_col] > 0.5:
                    work[n_row, n_col] += quant_error * weight

    return layer_map


# 0. physical config
transport_dir = r"C:\Users\Zh89\Desktop\transport"
input_file = os.path.join(transport_dir, "target_for_python.mat")
output_file = os.path.join(transport_dir, "dl_phase_init.mat")

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print("\n[INFO] PANN-Thermal-Holo start: quantization-aware + dose-aware + jittered init")

if not os.path.exists(input_file):
    raise FileNotFoundError(f"Cannot find transport input: {input_file}")

data = sio.loadmat(input_file)
design_key = "imag_target_design" if "imag_target_design" in data else "imag_target"
target_amp = torch.tensor(data[design_key], dtype=torch.float32, device=device)
target_amp_raw = torch.tensor(data["imag_target"], dtype=torch.float32, device=device)

Nx, Ny = int(data["Nx"].item()), int(data["Ny"].item())
Lx = float(data["Lx"].item())
lambda_water = float(data["lambda_water"].item())
z_target = float(data["z_target_dist"].item())
dz = float(data["dz"].item())
f0 = float(data["f0"].item())
c_water = float(data["c_water"].item())
c_board = float(data["c_board"].item())
thermal_sigma_px = float(data["thermal_sigma_px"].item()) if "thermal_sigma_px" in data else 1.0
min_base_layers = int(data["min_base_layers"].item()) if "min_base_layers" in data else 2

# 1. target shaping
resolution_limit_mm = 0.61 * lambda_water * 1000.0
sigma_mm = resolution_limit_mm * 0.35
sigma_px = sigma_mm / (Lx / Nx * 1000.0)

target_np = target_amp.detach().cpu().numpy().squeeze()
target_smooth_np = scipy.ndimage.gaussian_filter(target_np, sigma_px)
target_smooth = torch.tensor(target_smooth_np, dtype=torch.float32, device=device)
target_smooth = normalize_map(target_smooth)

target_raw_np = target_amp_raw.detach().cpu().numpy().squeeze()
line_target_np = (target_raw_np > 0.45).astype(np.float32)
halo_target_np = scipy.ndimage.gaussian_filter(line_target_np, max(1.0, thermal_sigma_px)) > 0.08
halo_ring_np = np.logical_and(halo_target_np, line_target_np < 0.5).astype(np.float32)
far_dark_np = np.logical_not(halo_target_np).astype(np.float32)

target_binary = torch.tensor(line_target_np, dtype=torch.float32, device=device)
halo_mask = torch.tensor(halo_ring_np, dtype=torch.float32, device=device)
far_dark_mask = torch.tensor(far_dark_np, dtype=torch.float32, device=device)
target_dose_np = scipy.ndimage.gaussian_filter(line_target_np, max(0.8, thermal_sigma_px))
target_dose = torch.tensor(target_dose_np, dtype=torch.float32, device=device)
target_dose = normalize_map(torch.maximum(target_dose, 0.35 * target_smooth))
target_raw_norm = normalize_map(target_amp_raw)

# 2. ASM operator
pad_factor = 2
Nx_pad, Ny_pad = Nx * pad_factor, Ny * pad_factor
dk = 2.0 * math.pi / (Lx * pad_factor)
kx = torch.arange(-Nx_pad / 2, Nx_pad / 2, device=device) * dk
ky = torch.arange(-Ny_pad / 2, Ny_pad / 2, device=device) * dk
Kx, Ky = torch.meshgrid(kx, ky, indexing="ij")
Kz_sq = (2.0 * math.pi / lambda_water) ** 2 - Kx**2 - Ky**2
Kz_sq = torch.clamp(Kz_sq, min=0.0)
H_forward = torch.exp(1j * torch.sqrt(Kz_sq) * z_target)


def propagate_asm(source_field):
    pad_len_x, pad_len_y = Nx // 2, Ny // 2
    padded_field = F.pad(source_field, (pad_len_y, pad_len_y, pad_len_x, pad_len_x), mode="constant", value=0)
    spectrum = torch.fft.fftshift(torch.fft.fft2(torch.fft.ifftshift(padded_field)))
    propagated = torch.fft.fftshift(torch.fft.ifft2(torch.fft.ifftshift(spectrum * H_forward)))
    return propagated[pad_len_x:-pad_len_x, pad_len_y:-pad_len_y]


# 3. quantization-aware optimization
k_diff = abs(2.0 * math.pi * f0 / c_water - 2.0 * math.pi * f0 / c_board)
phase_step = k_diff * dz
max_layer_index = min_base_layers + int(math.ceil(TWO_PI / phase_step)) + 1

x_vec = torch.linspace(-Lx / 2, Lx / 2, Nx, device=device)
y_vec = torch.linspace(-Lx / 2, Lx / 2, Ny, device=device)
Y_grid, X_grid = torch.meshgrid(y_vec, x_vec, indexing="ij")
source_mask = ((X_grid**2 + Y_grid**2) <= (32e-3) ** 2).float()

dark_weight = 1.0 + 8.0 * halo_mask + 12.0 * far_dark_mask
edge_weight = 1.0 + 2.5 * torch.abs(target_smooth - gaussian_blur2d(target_smooth, 1.0))
weight_map = dark_weight * edge_weight

initial_phase = (torch.rand(Nx, Ny, device=device) * TWO_PI) - math.pi
phase_map = torch.nn.Parameter(initial_phase)
phase_bias = torch.nn.Parameter(torch.zeros(1, device=device))

optimizer = optim.Adam([phase_map, phase_bias], lr=0.06)
scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=2500, eta_min=0.003)
epochs = 5000

best_loss = float("inf")
best_state = None

for epoch in range(epochs):
    optimizer.zero_grad()

    phase_quantized, layer_continuous = quantize_phase_ste(phase_map, phase_bias, phase_step, min_base_layers)
    source_field = torch.exp(1j * phase_quantized) * source_mask
    target_field = propagate_asm(source_field)

    pred_amp = torch.abs(target_field)
    pred_energy = normalize_map(pred_amp**2)
    pred_dose = normalize_map(gaussian_blur2d(pred_energy, thermal_sigma_px))

    loss_dose_corr = pearson_correlation_loss(pred_dose, target_dose)
    loss_dose_wmse = torch.mean(weight_map * (pred_dose - target_dose) ** 2)

    inside_vals = pred_dose[target_binary > 0.5]
    loss_uniformity = torch.var(inside_vals) if inside_vals.numel() > 4 else torch.tensor(0.0, device=device)

    halo_vals = pred_dose[halo_mask > 0.5]
    loss_halo = torch.mean(halo_vals**2) if halo_vals.numel() > 4 else torch.tensor(0.0, device=device)
    dark_vals = pred_dose[far_dark_mask > 0.5]
    loss_dark = torch.mean(dark_vals**2)

    current_ee = torch.sum(pred_energy * target_binary) / (torch.sum(pred_energy) + 1e-8)
    loss_ee = 1.0 - current_ee

    raw_mismatch = torch.mean((normalize_map(pred_amp) - target_raw_norm) ** 2)
    loss_layer_margin = torch.mean((layer_continuous - torch.round(layer_continuous)) ** 2)

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

    total_loss.backward()
    optimizer.step()
    scheduler.step()

    with torch.no_grad():
        phase_bias[:] = torch.remainder(phase_bias, TWO_PI)

    if total_loss.item() < best_loss:
        best_loss = total_loss.item()
        best_state = {
            "phase_map": phase_map.detach().clone(),
            "phase_bias": phase_bias.detach().clone(),
        }

    if (epoch + 1) % 100 == 0:
        print(
            f"Epoch [{epoch + 1}/{epochs}] | DoseCorr: {1.0 - loss_dose_corr.item():.4f} "
            f"| EE: {current_ee.item() * 100:.2f}% | Halo: {loss_halo.item():.4f} "
            f"| Dark: {loss_dark.item():.4f} | Loss: {total_loss.item():.4f}"
        )

# 4. export dithered result
phase_map_final = best_state["phase_map"]
phase_bias_final = best_state["phase_bias"]
wrapped_phase = torch.remainder(phase_map_final + phase_bias_final, TWO_PI)
layer_continuous = (wrapped_phase / phase_step + min_base_layers).detach().cpu().numpy()
mask_np = source_mask.detach().cpu().numpy()

dithered_layers = error_diffusion_quantize_layers(layer_continuous, mask_np, min_base_layers, max_layer_index)
dithered_phase = np.mod(dithered_layers * phase_step, TWO_PI).astype(np.float32)
dithered_phase *= mask_np.astype(np.float32)

sio.savemat(
    output_file,
    {
        "optimal_initial_phase": dithered_phase,
        "optimal_phase_bias": np.array([[phase_bias_final.item()]], dtype=np.float32),
        "optimal_layer_map": dithered_layers.astype(np.float32),
        "phase_step": np.array([[phase_step]], dtype=np.float32),
        "target_dose_design": target_dose.detach().cpu().numpy().astype(np.float32),
        "line_target_mask": target_binary.detach().cpu().numpy().astype(np.float32),
        "halo_target_mask": halo_mask.detach().cpu().numpy().astype(np.float32),
    },
)

print(f"\n[OK] Phase initialization written to: {output_file}")
