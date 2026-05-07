
import math
import os
import json

import numpy as np
import scipy.io as sio
import scipy.ndimage
import torch
import torch.nn.functional as F
import torch.optim as optim

from pann_quality_metrics import compute_cure_quality_terms

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
repo_dir = os.path.dirname(os.path.abspath(__file__))
branch_output_dir = os.path.join(repo_dir, "initial_phase_outputs")
os.makedirs(branch_output_dir, exist_ok=True)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print("\n[INFO] PANN-Pressure-Holo start: threshold coverage + target uniformity optimization")

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
target_threshold_norm = float(data["target_threshold_norm"].item()) if "target_threshold_norm" in data else 0.60
low_quantile_goal = float(data["low_quantile_goal"].item()) if "low_quantile_goal" in data else 0.88

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

target_weight = 1.0 + 5.0 * target_binary
dark_weight = 1.0 + 1.0 * halo_mask + 1.5 * far_dark_mask
weight_map = target_weight + dark_weight

initial_phase = (torch.rand(Nx, Ny, device=device) * TWO_PI) - math.pi
phase_map = torch.nn.Parameter(initial_phase)
phase_bias = torch.nn.Parameter(torch.zeros(1, device=device))

optimizer = optim.Adam([phase_map, phase_bias], lr=0.06)
scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=2500, eta_min=0.003)
epochs = 5000

best_loss = float("inf")
best_quality_score = -float("inf")
best_state = None
history = []

for epoch in range(epochs):
    optimizer.zero_grad()

    phase_quantized, layer_continuous = quantize_phase_ste(phase_map, phase_bias, phase_step, min_base_layers)
    source_field = torch.exp(1j * phase_quantized) * source_mask
    target_field = propagate_asm(source_field)

    pred_amp = torch.abs(target_field)
    pred_amp_norm = normalize_map(pred_amp)
    quality_terms = compute_cure_quality_terms(
        pred_amp_norm,
        target_binary,
        halo_mask,
        far_dark_mask,
        threshold_norm=target_threshold_norm,
        low_quantile_goal=low_quantile_goal,
    )
    pred_energy = quality_terms["pred_energy"]

    loss_amp_corr = pearson_correlation_loss(pred_amp_norm, target_raw_norm)
    loss_amp_wmse = torch.mean(weight_map * (pred_amp_norm - target_raw_norm) ** 2)

    loss_energy_uniformity = quality_terms["energy_uniformity_loss"]
    loss_amp_uniformity = quality_terms["amp_uniformity_loss"]
    loss_threshold = quality_terms["threshold_loss"]
    loss_low_quantile = quality_terms["low_quantile_loss"]
    loss_halo = quality_terms["halo_loss"]
    loss_dark = quality_terms["dark_mean_loss"]
    loss_dark_area = quality_terms["dark_area_loss"]
    current_ee = quality_terms["energy_efficiency"]
    loss_ee = 1.0 - current_ee

    loss_layer_margin = torch.mean((layer_continuous - torch.round(layer_continuous)) ** 2)
    quality_score = quality_terms["quality_score"] + 0.25 * (1.0 - loss_amp_corr)

    total_loss = (
        7.0 * loss_threshold
        + 5.0 * loss_low_quantile
        + 3.5 * loss_amp_uniformity
        + 2.0 * loss_energy_uniformity
        + 0.8 * loss_ee
        + 0.7 * loss_amp_corr
        + 0.4 * loss_amp_wmse
        + 0.6 * loss_dark_area
        + 0.2 * loss_dark
        + 0.4 * loss_halo
        + 0.15 * loss_layer_margin
    )

    with torch.no_grad():
        target_mean = torch.mean(pred_amp[target_binary > 0.5]) if torch.any(target_binary > 0.5) else torch.tensor(0.0, device=device)
        far_dark_mean = torch.mean(pred_amp[far_dark_mask > 0.5]) if torch.any(far_dark_mask > 0.5) else torch.tensor(0.0, device=device)
        target_dark_contrast = target_mean / (far_dark_mean + 1e-8)
        phase_margin = torch.mean(torch.abs(layer_continuous - torch.round(layer_continuous)))
        history.append(
            [
                epoch + 1,
                float(total_loss.detach().cpu()),
                float((1.0 - loss_amp_corr).detach().cpu()),
                float(current_ee.detach().cpu()),
                float(loss_amp_wmse.detach().cpu()),
                float(loss_energy_uniformity.detach().cpu()),
                float(loss_halo.detach().cpu()),
                float(loss_dark.detach().cpu()),
                float(loss_dark_area.detach().cpu()),
                float(phase_margin.detach().cpu()),
                float(quality_terms["target_cv"].detach().cpu()),
                float(target_dark_contrast.detach().cpu()),
                float(loss_threshold.detach().cpu()),
                float(quality_terms["target_p10_over_p50"].detach().cpu()),
                float(quality_terms["dark_area_fraction"].detach().cpu()),
                float(quality_score.detach().cpu()),
                float(quality_terms["target_coverage"].detach().cpu()),
                float(loss_low_quantile.detach().cpu()),
            ]
        )

    total_loss.backward()
    optimizer.step()
    scheduler.step()

    with torch.no_grad():
        phase_bias[:] = torch.remainder(phase_bias, TWO_PI)

    if total_loss.item() < best_loss:
        best_loss = total_loss.item()

    if quality_score.item() > best_quality_score:
        best_quality_score = quality_score.item()
        best_state = {
            "phase_map": phase_map.detach().clone(),
            "phase_bias": phase_bias.detach().clone(),
            "epoch": epoch + 1,
        }

    if (epoch + 1) % 100 == 0:
        print(
            f"Epoch [{epoch + 1}/{epochs}] | AmpCorr: {1.0 - loss_amp_corr.item():.4f} "
            f"| Coverage: {quality_terms['target_coverage'].item() * 100:.2f}% | P10/P50: {quality_terms['target_p10_over_p50'].item():.4f} "
            f"| CV: {quality_terms['target_cv'].item():.4f} | EE: {current_ee.item() * 100:.2f}% "
            f"| ThrLoss: {loss_threshold.item():.4f} | DarkArea: {loss_dark_area.item():.4f} "
            f"| Quality: {quality_score.item():.4f} | Loss: {total_loss.item():.4f}"
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

history_np = np.array(history, dtype=np.float32)
best_source_field = torch.exp(1j * torch.tensor(dithered_phase, dtype=torch.float32, device=device)) * source_mask
best_target_field = propagate_asm(best_source_field)
best_amp = torch.abs(best_target_field)
best_amp_norm = normalize_map(best_amp)
best_quality_terms = compute_cure_quality_terms(
    best_amp_norm,
    target_binary,
    halo_mask,
    far_dark_mask,
    threshold_norm=target_threshold_norm,
    low_quantile_goal=low_quantile_goal,
)
best_energy = best_quality_terms["pred_energy"]
best_target_vals = best_amp_norm[target_binary > 0.5]
best_dark_vals = best_amp_norm[far_dark_mask > 0.5]
best_target_p10 = torch.quantile(best_target_vals, 0.10) if best_target_vals.numel() > 4 else torch.tensor(0.0, device=device)
best_target_p50 = torch.quantile(best_target_vals, 0.50) if best_target_vals.numel() > 4 else torch.tensor(0.0, device=device)
best_metrics = {
    "best_loss": float(best_loss),
    "best_quality_score": float(best_quality_score),
    "selected_epoch": int(best_state["epoch"]),
    "final_epoch": int(epochs),
    "device": str(device),
    "target_threshold_norm": float(target_threshold_norm),
    "low_quantile_goal": float(low_quantile_goal),
    "amplitude_corr": float(1.0 - pearson_correlation_loss(best_amp_norm, target_raw_norm).detach().cpu()),
    "energy_efficiency": float(best_quality_terms["energy_efficiency"].detach().cpu()),
    "target_coverage": float(best_quality_terms["target_coverage"].detach().cpu()),
    "target_uniformity_cv": float((torch.std(best_target_vals) / (torch.mean(best_target_vals) + 1e-8)).detach().cpu()) if best_target_vals.numel() > 1 else 0.0,
    "target_p10_over_p50": float((best_target_p10 / (best_target_p50 + 1e-8)).detach().cpu()),
    "dark_mean_norm": float(torch.mean(best_dark_vals).detach().cpu()) if best_dark_vals.numel() > 1 else 0.0,
    "dark_area_fraction": float(best_quality_terms["dark_area_fraction"].detach().cpu()),
    "phase_bias_rad": float(phase_bias_final.item()),
    "phase_step_rad": float(phase_step),
    "layer_min": int(np.min(dithered_layers[mask_np > 0.5])),
    "layer_max": int(np.max(dithered_layers[mask_np > 0.5])),
    "layer_std": float(np.std(dithered_layers[mask_np > 0.5])),
}

sio.savemat(
    output_file,
    {
        "optimal_initial_phase": dithered_phase,
        "optimal_phase_bias": np.array([[phase_bias_final.item()]], dtype=np.float32),
        "optimal_layer_map": dithered_layers.astype(np.float32),
        "phase_step": np.array([[phase_step]], dtype=np.float32),
        "line_target_mask": target_binary.detach().cpu().numpy().astype(np.float32),
        "halo_target_mask": halo_mask.detach().cpu().numpy().astype(np.float32),
        "python_loss_history": history_np,
        "python_metrics": best_metrics,
        "python_asm_amp_norm": best_amp_norm.detach().cpu().numpy().astype(np.float32),
        "target_threshold_norm": np.array([[target_threshold_norm]], dtype=np.float32),
        "low_quantile_goal": np.array([[low_quantile_goal]], dtype=np.float32),
    },
)

sio.savemat(
    os.path.join(branch_output_dir, "pann_phase_output_snapshot.mat"),
    {
        "optimal_initial_phase": dithered_phase,
        "optimal_phase_bias": np.array([[phase_bias_final.item()]], dtype=np.float32),
        "optimal_layer_map": dithered_layers.astype(np.float32),
        "python_loss_history": history_np,
        "python_metrics": best_metrics,
        "python_asm_amp_norm": best_amp_norm.detach().cpu().numpy().astype(np.float32),
        "target_threshold_norm": np.array([[target_threshold_norm]], dtype=np.float32),
        "low_quantile_goal": np.array([[low_quantile_goal]], dtype=np.float32),
    },
)

np.savetxt(
    os.path.join(branch_output_dir, "pann_training_history.csv"),
    history_np,
    delimiter=",",
    header="epoch,total_loss,amplitude_corr,energy_efficiency,amplitude_wmse,energy_uniformity_loss,halo_loss,dark_mean_loss,dark_area_loss,phase_margin,target_cv,target_dark_contrast,threshold_loss,target_p10_over_p50,dark_area_fraction,quality_score,target_coverage,low_quantile_loss",
    comments="",
)

with open(os.path.join(branch_output_dir, "pann_training_summary.json"), "w", encoding="utf-8") as f:
    json.dump(best_metrics, f, indent=2)

try:
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(2, 2, figsize=(11, 8), constrained_layout=True)
    axes[0, 0].plot(history_np[:, 0], history_np[:, 1])
    axes[0, 0].set_title("Total loss")
    axes[0, 0].set_xlabel("Epoch")
    axes[0, 0].grid(True, alpha=0.3)
    axes[0, 1].plot(history_np[:, 0], history_np[:, 16], label="Target coverage")
    axes[0, 1].plot(history_np[:, 0], history_np[:, 13], label="Target P10/P50")
    axes[0, 1].set_title("Threshold target quality")
    axes[0, 1].set_xlabel("Epoch")
    axes[0, 1].legend()
    axes[0, 1].grid(True, alpha=0.3)
    axes[1, 0].plot(history_np[:, 0], history_np[:, 10], label="Target CV")
    axes[1, 0].plot(history_np[:, 0], history_np[:, 14], label="Dark area fraction")
    axes[1, 0].set_title("Cure-quality constraints")
    axes[1, 0].set_xlabel("Epoch")
    axes[1, 0].legend()
    axes[1, 0].grid(True, alpha=0.3)
    axes[1, 1].imshow(best_amp_norm.detach().cpu().numpy(), cmap="hot")
    axes[1, 1].set_title("Best ASM amplitude")
    axes[1, 1].axis("off")
    fig.savefig(os.path.join(branch_output_dir, "pann_training_metrics.png"), dpi=220)
    plt.close(fig)
except Exception as plot_error:
    print(f"[WARN] Could not write PANN metric figure: {plot_error}")

print(f"\n[OK] Phase initialization written to: {output_file}")
print(f"[OK] Branch metrics written to: {branch_output_dir}")
