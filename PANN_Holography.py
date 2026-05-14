
import math
import os
import json

import numpy as np
import scipy.io as sio
import scipy.ndimage
import torch
import torch.nn.functional as F
import torch.optim as optim

from pann_quality_metrics import aggregate_z_quality_terms, compute_cure_quality_terms

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


def matlab_string(value):
    arr = np.asarray(value)
    if arr.dtype.kind in {"U", "S"}:
        return "".join(arr.reshape(-1).astype(str)).strip()
    return str(arr.squeeze())


def current_git_commit_short(repo_path):
    head_path = os.path.join(repo_path, ".git", "HEAD")
    try:
        with open(head_path, "r", encoding="utf-8") as f:
            head = f.read().strip()
        if head.startswith("ref:"):
            ref_path = os.path.join(repo_path, ".git", head.split(" ", 1)[1])
            with open(ref_path, "r", encoding="utf-8") as f:
                return f.read().strip()[:7]
        return head[:7]
    except OSError:
        return "nogit"


def damped_periodic_lr_lambda(epoch, restart_cycle, restart_decay, min_ratio):
    """Periodic cosine exploration with a decaying peak each full cycle."""
    cycle_len = max(1, int(restart_cycle))
    epoch_now = int(epoch)
    cycle_idx = epoch_now // cycle_len
    position = (epoch_now % cycle_len) / cycle_len

    peak_ratio = max(min_ratio, float(restart_decay) ** cycle_idx)
    oscillation = 0.5 * (1.0 + math.cos(2.0 * math.pi * position))
    return min_ratio + (peak_ratio - min_ratio) * oscillation


# 0. physical config
transport_dir = r"C:\Users\Zh89\Desktop\transport"
input_file = os.path.join(transport_dir, "target_for_python.mat")
output_file = os.path.join(transport_dir, "dl_phase_init.mat")
repo_dir = os.path.dirname(os.path.abspath(__file__))
git_commit_short = current_git_commit_short(repo_dir)
branch_output_dir = os.path.join(repo_dir, "initial_phase_outputs", git_commit_short)
os.makedirs(branch_output_dir, exist_ok=True)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print("\n[INFO] PANN-Pressure-Holo start: board-constrained target narrow-band optimization")

if not os.path.exists(input_file):
    raise FileNotFoundError(f"Cannot find transport input: {input_file}")

data = sio.loadmat(input_file)
transport_is_current = True
if "branch_output_dir" in data:
    transport_output_dir = matlab_string(data["branch_output_dir"])
    if os.path.basename(os.path.normpath(transport_output_dir)) == git_commit_short:
        branch_output_dir = transport_output_dir
        os.makedirs(branch_output_dir, exist_ok=True)
    else:
        transport_is_current = False
        print(
            f"[WARN] Ignoring stale branch_output_dir from transport: {transport_output_dir}. "
            f"Using current commit output: {branch_output_dir}"
        )
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
target_mean_amp_goal_ratio = float(data["target_mean_amp_goal_ratio"].item()) if "target_mean_amp_goal_ratio" in data else 0.12
epochs = int(data["python_epochs"].item()) if "python_epochs" in data else 10000
learning_rate = float(data["python_learning_rate"].item()) if "python_learning_rate" in data else 0.06
min_epochs = int(data["python_min_epochs"].item()) if "python_min_epochs" in data else min(6500, epochs)
early_stop_patience = (
    int(data["python_early_stop_patience"].item()) if "python_early_stop_patience" in data else 4200
)
python_rng_seed = int(data["python_rng_seed"].item()) if "python_rng_seed" in data else 9426
lr_restart_cycle = int(data["python_lr_restart_cycle"].item()) if "python_lr_restart_cycle" in data else 5000
lr_restart_decay = float(data["python_lr_restart_decay"].item()) if "python_lr_restart_decay" in data else 0.82
lr_min_ratio = float(data["python_lr_min_ratio"].item()) if "python_lr_min_ratio" in data else 0.05
if transport_is_current and "python_z_constraint_offsets_m" in data:
    z_constraint_offsets = np.asarray(data["python_z_constraint_offsets_m"], dtype=np.float32).reshape(-1)
else:
    z_constraint_offsets = np.array([0.0], dtype=np.float32)
if not np.any(np.isclose(z_constraint_offsets, 0.0)):
    z_constraint_offsets = np.sort(np.append(z_constraint_offsets, 0.0)).astype(np.float32)

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
propagating_mask = Kz_sq > 0
Kz = torch.zeros_like(Kz_sq)
Kz[propagating_mask] = torch.sqrt(Kz_sq[propagating_mask])
kernel_dtype = torch.complex64 if Kz.dtype == torch.float32 else torch.complex128


def make_forward_kernel(distance):
    H = torch.zeros(Kz.shape, dtype=kernel_dtype, device=device)
    phase = Kz[propagating_mask] * float(distance)
    H[propagating_mask] = torch.cos(phase).to(kernel_dtype) + 1j * torch.sin(phase).to(kernel_dtype)
    return H


H_forward_by_offset = {
    float(offset): make_forward_kernel(z_target + float(offset))
    for offset in z_constraint_offsets
}
H_forward = H_forward_by_offset[min(H_forward_by_offset.keys(), key=lambda offset: abs(offset))]
asm_propagating_fraction = float(torch.mean(propagating_mask.float()).detach().cpu())
asm_evanescent_fraction = 1.0 - asm_propagating_fraction
print(
    f"[INFO] ASM kernel: propagating {asm_propagating_fraction * 100:.2f}% | "
    f"evanescent filtered {asm_evanescent_fraction * 100:.2f}%"
)


def propagate_asm(source_field, H_forward_now=H_forward):
    pad_len_x, pad_len_y = Nx // 2, Ny // 2
    padded_field = F.pad(source_field, (pad_len_y, pad_len_y, pad_len_x, pad_len_x), mode="constant", value=0)
    spectrum = torch.fft.fftshift(torch.fft.fft2(torch.fft.ifftshift(padded_field)))
    propagated = torch.fft.fftshift(torch.fft.ifft2(torch.fft.ifftshift(spectrum * H_forward_now)))
    return propagated[pad_len_x:-pad_len_x, pad_len_y:-pad_len_y]


# 3. quantization-aware optimization
k_diff = abs(2.0 * math.pi * f0 / c_water - 2.0 * math.pi * f0 / c_board)
phase_step = k_diff * dz
max_layer_index = min_base_layers + int(math.ceil(TWO_PI / phase_step)) + 1

x_vec = torch.linspace(-Lx / 2, Lx / 2, Nx, device=device)
y_vec = torch.linspace(-Lx / 2, Lx / 2, Ny, device=device)
Y_grid, X_grid = torch.meshgrid(y_vec, x_vec, indexing="ij")
if "source_mask" in data:
    source_mask_np = np.asarray(data["source_mask"], dtype=np.float32).squeeze()
    source_mask = torch.tensor(source_mask_np, dtype=torch.float32, device=device)
else:
    source_mask = ((X_grid**2 + Y_grid**2) <= (32e-3) ** 2).float()
target_mean_amp_goal = target_mean_amp_goal_ratio * math.sqrt(
    float(torch.sum(source_mask).detach().cpu()) / (float(torch.sum(target_binary).detach().cpu()) + 1e-8)
)

target_weight = 1.0 + 5.0 * target_binary
dark_weight = 1.0 + 1.0 * halo_mask + 1.5 * far_dark_mask
weight_map = target_weight + dark_weight

torch.manual_seed(python_rng_seed)
if torch.cuda.is_available():
    torch.cuda.manual_seed_all(python_rng_seed)
initial_phase = (torch.rand(Nx, Ny, device=device) * TWO_PI) - math.pi
phase_map = torch.nn.Parameter(initial_phase)
phase_bias = torch.nn.Parameter(torch.zeros(1, device=device))

optimizer = optim.AdamW([phase_map, phase_bias], lr=learning_rate, weight_decay=0.0)
scheduler = optim.lr_scheduler.LambdaLR(
    optimizer,
    lr_lambda=lambda epoch: damped_periodic_lr_lambda(epoch, lr_restart_cycle, lr_restart_decay, lr_min_ratio),
)

best_loss = float("inf")
best_quality_score = -float("inf")
best_state = None
best_epoch = 0
stop_reason = "max_epochs"
top_quality_records = []
history = []

for epoch in range(epochs):
    optimizer.zero_grad()

    phase_quantized, layer_continuous = quantize_phase_ste(phase_map, phase_bias, phase_step, min_base_layers)
    source_field = torch.exp(1j * phase_quantized) * source_mask
    quality_terms_by_z = []
    corr_losses = []
    wmse_losses = []
    center_quality_terms = None
    for offset, H_now in H_forward_by_offset.items():
        target_field = propagate_asm(source_field, H_now)
        pred_amp = torch.abs(target_field)
        pred_amp_norm = normalize_map(pred_amp)
        terms_now = compute_cure_quality_terms(
            pred_amp_norm,
            target_binary,
            halo_mask,
            far_dark_mask,
            pred_amp_raw=pred_amp,
            threshold_norm=target_threshold_norm,
            low_quantile_goal=low_quantile_goal,
            target_mean_amp_goal=target_mean_amp_goal,
        )
        quality_terms_by_z.append(terms_now)
        corr_losses.append(pearson_correlation_loss(pred_amp_norm, target_raw_norm))
        wmse_losses.append(torch.mean(weight_map * (pred_amp_norm - target_raw_norm) ** 2))
        if abs(offset) < 1e-12:
            center_quality_terms = terms_now

    if center_quality_terms is None:
        center_quality_terms = quality_terms_by_z[len(quality_terms_by_z) // 2]

    z_terms = aggregate_z_quality_terms(quality_terms_by_z)
    loss_amp_corr = torch.mean(torch.stack(corr_losses))
    loss_amp_wmse = torch.mean(torch.stack(wmse_losses))

    loss_energy_uniformity = z_terms["mean_energy_uniformity_loss"]
    loss_amp_uniformity = z_terms["mean_amp_uniformity_loss"]
    loss_threshold = z_terms["mean_threshold_loss"]
    loss_low_quantile = z_terms["mean_low_quantile_loss"]
    loss_peak_balance = z_terms["mean_peak_balance_loss"]
    loss_dark_area = z_terms["mean_dark_area_loss"]
    loss_dark_relative = z_terms["mean_dark_relative_loss"]
    loss_halo = z_terms["mean_halo_loss"]
    loss_dark = z_terms["mean_dark_mean_loss"]
    current_ee = z_terms["mean_energy_efficiency"]

    loss_layer_margin = torch.mean((layer_continuous - torch.round(layer_continuous)) ** 2)
    quality_score = (
        z_terms["mean_quality_score"]
        + 0.5 * z_terms["worst_quality_score"]
        + 0.10 * (1.0 - loss_amp_corr)
    )

    total_loss = (
        2.0 * loss_threshold
        + 7.0 * loss_low_quantile
        + 5.0 * z_terms["worst_low_quantile_loss"]
        + 5.0 * z_terms["worst_cv_loss"]
        + 5.0 * loss_peak_balance
        + 3.0 * z_terms["worst_peak_balance_loss"]
        + 7.0 * loss_amp_uniformity
        + 2.5 * loss_energy_uniformity
        + 4.0 * loss_dark_relative
        + 2.5 * z_terms["worst_dark_relative_loss"]
        + 1.0 * loss_dark_area
        + 0.35 * loss_amp_corr
        + 0.20 * loss_amp_wmse
        + 0.15 * loss_layer_margin
    )

    with torch.no_grad():
        phase_margin = torch.mean(torch.abs(layer_continuous - torch.round(layer_continuous)))
        candidate_phase_map = phase_map.detach().clone()
        candidate_phase_bias = phase_bias.detach().clone()
        candidate_learning_rate = float(optimizer.param_groups[0]["lr"])
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
                float(z_terms["mean_target_cv"].detach().cpu()),
                float(z_terms["worst_target_cv"].detach().cpu()),
                float(loss_threshold.detach().cpu()),
                float(z_terms["mean_target_p10_over_p50"].detach().cpu()),
                float(z_terms["mean_dark_area_fraction"].detach().cpu()),
                float(quality_score.detach().cpu()),
                float(z_terms["mean_target_coverage"].detach().cpu()),
                float(loss_low_quantile.detach().cpu()),
                float(loss_dark_relative.detach().cpu()),
                float(z_terms["mean_target_mean_raw"].detach().cpu()),
                float(z_terms["mean_target_to_global_mean"].detach().cpu()),
                float(z_terms["worst_target_coverage"].detach().cpu()),
                float(z_terms["worst_target_p10_over_p50"].detach().cpu()),
                float(z_terms["mean_target_p05_over_p50"].detach().cpu()),
                float(z_terms["mean_target_p90_over_mean"].detach().cpu()),
                float(z_terms["mean_target_p95_over_mean"].detach().cpu()),
                float(z_terms["mean_target_peak_over_mean"].detach().cpu()),
                float(loss_peak_balance.detach().cpu()),
                float(z_terms["mean_dark_p99_over_target_p50"].detach().cpu()),
                float(z_terms["mean_dark_peak_over_target_p50"].detach().cpu()),
                float(z_terms["mean_dark_high_area_fraction"].detach().cpu()),
                candidate_learning_rate,
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
        best_epoch = epoch + 1
        best_state = {
            "phase_map": candidate_phase_map,
            "phase_bias": candidate_phase_bias,
            "epoch": epoch + 1,
            "learning_rate": candidate_learning_rate,
        }
        top_quality_records.append(
            {
                "epoch": epoch + 1,
                "quality_score": float(quality_score.detach().cpu()),
                "total_loss": float(total_loss.detach().cpu()),
                "amplitude_corr": float((1.0 - loss_amp_corr).detach().cpu()),
                "mean_energy_efficiency": float(current_ee.detach().cpu()),
                "mean_target_cv": float(z_terms["mean_target_cv"].detach().cpu()),
                "mean_target_p10_over_p50": float(z_terms["mean_target_p10_over_p50"].detach().cpu()),
                "mean_target_peak_over_mean": float(z_terms["mean_target_peak_over_mean"].detach().cpu()),
                "mean_dark_p99_over_target_p50": float(z_terms["mean_dark_p99_over_target_p50"].detach().cpu()),
                "mean_dark_peak_over_target_p50": float(z_terms["mean_dark_peak_over_target_p50"].detach().cpu()),
                "mean_target_coverage": float(z_terms["mean_target_coverage"].detach().cpu()),
                "learning_rate": optimizer.param_groups[0]["lr"],
            }
        )
        top_quality_records = sorted(top_quality_records, key=lambda item: item["quality_score"], reverse=True)[:5]

    if (epoch + 1) % 100 == 0:
        print(
            f"Epoch [{epoch + 1}/{epochs}] | AmpCorr: {1.0 - loss_amp_corr.item():.4f} "
            f"| MeanCov: {z_terms['mean_target_coverage'].item() * 100:.2f}% | WorstCov: {z_terms['worst_target_coverage'].item() * 100:.2f}% "
            f"| WorstP10/P50: {z_terms['worst_target_p10_over_p50'].item():.4f} "
            f"| WorstCV: {z_terms['worst_target_cv'].item():.4f} | EE: {current_ee.item() * 100:.2f}% "
            f"| P95/Mean: {z_terms['mean_target_p95_over_mean'].item():.3f} | Peak/Mean: {z_terms['mean_target_peak_over_mean'].item():.3f} "
            f"| DarkP99/P50: {z_terms['mean_dark_p99_over_target_p50'].item():.3f} "
            f"| DarkPeak/P50: {z_terms['mean_dark_peak_over_target_p50'].item():.3f} "
            f"| DarkRel: {loss_dark_relative.item():.4f} | DarkArea: {loss_dark_area.item():.4f} "
            f"| Quality: {quality_score.item():.4f} | Loss: {total_loss.item():.4f}"
        )

    epochs_to_next_restart = lr_restart_cycle - ((epoch + 1) % lr_restart_cycle)
    near_next_restart = 0 < epochs_to_next_restart <= 600
    if epoch + 1 >= min_epochs and epoch + 1 - best_epoch >= early_stop_patience and not near_next_restart:
        stop_reason = f"early_stop_no_quality_gain_{early_stop_patience}"
        print(
            f"[INFO] Early stopping at epoch {epoch + 1}: best quality "
            f"{best_quality_score:.4f} was reached at epoch {best_epoch}."
        )
        break

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
    pred_amp_raw=best_amp,
    threshold_norm=target_threshold_norm,
    low_quantile_goal=low_quantile_goal,
    target_mean_amp_goal=target_mean_amp_goal,
)
best_energy = best_quality_terms["pred_energy"]
best_target_vals = best_amp_norm[target_binary > 0.5]
best_dark_vals = best_amp_norm[far_dark_mask > 0.5]
best_target_p05 = torch.quantile(best_target_vals, 0.05) if best_target_vals.numel() > 4 else torch.tensor(0.0, device=device)
best_target_p10 = torch.quantile(best_target_vals, 0.10) if best_target_vals.numel() > 4 else torch.tensor(0.0, device=device)
best_target_p50 = torch.quantile(best_target_vals, 0.50) if best_target_vals.numel() > 4 else torch.tensor(0.0, device=device)
best_target_p90 = torch.quantile(best_target_vals, 0.90) if best_target_vals.numel() > 4 else torch.tensor(0.0, device=device)
best_target_p95 = torch.quantile(best_target_vals, 0.95) if best_target_vals.numel() > 4 else torch.tensor(0.0, device=device)
best_target_mean = torch.mean(best_target_vals) if best_target_vals.numel() > 4 else torch.tensor(0.0, device=device)
best_target_peak = torch.max(best_target_vals) if best_target_vals.numel() > 4 else torch.tensor(0.0, device=device)
best_metrics = {
    "best_loss": float(best_loss),
    "best_quality_score": float(best_quality_score),
    "selected_epoch": int(best_state["epoch"]),
    "final_epoch": int(history_np[-1, 0]) if history_np.size else 0,
    "configured_epochs": int(epochs),
    "stop_reason": stop_reason,
    "selected_learning_rate": float(best_state["learning_rate"]),
    "initial_learning_rate": float(learning_rate),
    "rng_seed": int(python_rng_seed),
    "lr_schedule": "damped_periodic_cosine",
    "lr_restart_cycle": int(lr_restart_cycle),
    "lr_restart_decay": float(lr_restart_decay),
    "lr_min_ratio": float(lr_min_ratio),
    "min_epochs": int(min_epochs),
    "early_stop_patience": int(early_stop_patience),
    "top_quality_records_json": json.dumps(top_quality_records),
    "device": str(device),
    "asm_propagating_fraction": asm_propagating_fraction,
    "asm_evanescent_fraction": asm_evanescent_fraction,
    "target_threshold_norm": float(target_threshold_norm),
    "low_quantile_goal": float(low_quantile_goal),
    "target_mean_amp_goal": float(target_mean_amp_goal),
    "target_mean_amp_goal_ratio": float(target_mean_amp_goal_ratio),
    "z_constraint_offsets_m": z_constraint_offsets.astype(float).tolist(),
    "amplitude_corr": float(1.0 - pearson_correlation_loss(best_amp_norm, target_raw_norm).detach().cpu()),
    "energy_efficiency": float(best_quality_terms["energy_efficiency"].detach().cpu()),
    "target_coverage": float(best_quality_terms["target_coverage"].detach().cpu()),
    "target_mean_amp_raw": float(best_quality_terms["target_mean_raw"].detach().cpu()),
    "target_to_global_mean": float(best_quality_terms["target_to_global_mean"].detach().cpu()),
    "target_uniformity_cv": float((torch.std(best_target_vals) / (torch.mean(best_target_vals) + 1e-8)).detach().cpu()) if best_target_vals.numel() > 1 else 0.0,
    "target_p05_over_p50": float((best_target_p05 / (best_target_p50 + 1e-8)).detach().cpu()),
    "target_p10_over_p50": float((best_target_p10 / (best_target_p50 + 1e-8)).detach().cpu()),
    "target_p90_over_mean": float((best_target_p90 / (best_target_mean + 1e-8)).detach().cpu()),
    "target_p95_over_mean": float((best_target_p95 / (best_target_mean + 1e-8)).detach().cpu()),
    "target_peak_over_mean": float((best_target_peak / (best_target_mean + 1e-8)).detach().cpu()),
    "target_peak_balance_loss": float(best_quality_terms["peak_balance_loss"].detach().cpu()),
    "dark_mean_norm": float(torch.mean(best_dark_vals).detach().cpu()) if best_dark_vals.numel() > 1 else 0.0,
    "dark_area_fraction": float(best_quality_terms["dark_area_fraction"].detach().cpu()),
    "dark_high_area_fraction": float(best_quality_terms["dark_high_area_fraction"].detach().cpu()),
    "dark_p95_over_target_p50": float(best_quality_terms["dark_p95_over_target_p50"].detach().cpu()),
    "dark_p99_over_target_p50": float(best_quality_terms["dark_p99_over_target_p50"].detach().cpu()),
    "dark_peak_over_target_p50": float(best_quality_terms["dark_peak_over_target_p50"].detach().cpu()),
    "dark_relative_loss": float(best_quality_terms["dark_relative_loss"].detach().cpu()),
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
        "target_mean_amp_goal": np.array([[target_mean_amp_goal]], dtype=np.float32),
        "z_constraint_offsets_m": z_constraint_offsets.astype(np.float32),
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
        "target_mean_amp_goal": np.array([[target_mean_amp_goal]], dtype=np.float32),
        "z_constraint_offsets_m": z_constraint_offsets.astype(np.float32),
    },
)

np.savetxt(
    os.path.join(branch_output_dir, "pann_training_history.csv"),
    history_np,
    delimiter=",",
    header="epoch,total_loss,amplitude_corr,mean_energy_efficiency,amplitude_wmse,mean_energy_uniformity_loss,mean_halo_loss,mean_dark_loss,mean_dark_area_loss,phase_margin,mean_target_cv,worst_target_cv,mean_threshold_loss,mean_target_p10_over_p50,mean_dark_area_fraction,quality_score,mean_target_coverage,mean_low_quantile_loss,mean_dark_relative_loss,mean_target_mean_amp_raw,mean_target_to_global_mean,worst_target_coverage,worst_target_p10_over_p50,mean_target_p05_over_p50,mean_target_p90_over_mean,mean_target_p95_over_mean,mean_target_peak_over_mean,mean_peak_balance_loss,mean_dark_p99_over_target_p50,mean_dark_peak_over_target_p50,mean_dark_high_area_fraction,learning_rate",
    comments="",
)

json_metrics = dict(best_metrics)
json_metrics["top_quality_records"] = top_quality_records
with open(os.path.join(branch_output_dir, "pann_training_summary.json"), "w", encoding="utf-8") as f:
    json.dump(json_metrics, f, indent=2)

try:
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(2, 2, figsize=(11, 8), constrained_layout=True)
    axes[0, 0].plot(history_np[:, 0], history_np[:, 1])
    axes[0, 0].set_title("Total loss")
    axes[0, 0].set_xlabel("Epoch")
    axes[0, 0].grid(True, alpha=0.3)
    axes[0, 1].plot(history_np[:, 0], history_np[:, 16], label="Mean coverage")
    axes[0, 1].plot(history_np[:, 0], history_np[:, 21], label="Worst coverage")
    axes[0, 1].set_title("Threshold coverage")
    axes[0, 1].set_xlabel("Epoch")
    axes[0, 1].legend()
    axes[0, 1].grid(True, alpha=0.3)
    axes[1, 0].plot(history_np[:, 0], history_np[:, 10], label="Mean target CV")
    axes[1, 0].plot(history_np[:, 0], history_np[:, 11], label="Worst target CV")
    axes[1, 0].plot(history_np[:, 0], history_np[:, 25], label="P95/Mean")
    axes[1, 0].plot(history_np[:, 0], history_np[:, 26], label="Peak/Mean")
    axes[1, 0].plot(history_np[:, 0], history_np[:, 28], label="Dark P99/P50")
    axes[1, 0].plot(history_np[:, 0], history_np[:, 29], label="Dark peak/P50")
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
