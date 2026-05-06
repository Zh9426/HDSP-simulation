import argparse
import math
from pathlib import Path

import numpy as np
import scipy.io as sio
import scipy.ndimage

TWO_PI = 2.0 * math.pi


def normalize_map(values: np.ndarray) -> np.ndarray:
    return values / (np.max(values) + 1e-12)


def pearson_score(pred: np.ndarray, target: np.ndarray) -> float:
    pred_c = pred.ravel() - np.mean(pred)
    target_c = target.ravel() - np.mean(target)
    denom = math.sqrt(float(np.sum(pred_c**2) * np.sum(target_c**2))) + 1e-12
    return float(np.sum(pred_c * target_c) / denom)


def matlab_scalar(mat_struct, field_name: str) -> float:
    value = getattr(mat_struct, field_name)
    return float(np.squeeze(value))


def build_asm_kernel(cfg) -> np.ndarray:
    nx = int(matlab_scalar(cfg, "Nx"))
    ny = int(matlab_scalar(cfg, "Ny"))
    pad_factor = int(matlab_scalar(cfg, "pad_factor"))
    nx_pad = nx * pad_factor
    ny_pad = ny * pad_factor
    lx = matlab_scalar(cfg, "Lx")
    ly = matlab_scalar(cfg, "Ly")
    f0 = matlab_scalar(cfg, "f0")
    c_water = matlab_scalar(cfg, "c_water")
    z_target_dist = matlab_scalar(cfg, "z_target_dist")

    dkx = 2.0 * math.pi / (lx * pad_factor)
    dky = 2.0 * math.pi / (ly * pad_factor)
    kx = np.arange(-nx_pad / 2, nx_pad / 2, dtype=np.float64) * dkx
    ky = np.arange(-ny_pad / 2, ny_pad / 2, dtype=np.float64) * dky
    k_x, k_y = np.meshgrid(kx, ky, indexing="ij")
    k0 = 2.0 * math.pi * f0 / c_water
    kz_sq = k0**2 - k_x**2 - k_y**2
    propagating = kz_sq > 0
    kz = np.zeros_like(kz_sq)
    kz[propagating] = np.sqrt(kz_sq[propagating])
    h_forward = np.zeros_like(kz_sq, dtype=np.complex64)
    h_forward[propagating] = np.exp(1j * kz[propagating] * z_target_dist)
    return h_forward


def propagate_asm(source_field: np.ndarray, h_forward: np.ndarray, pad_factor: int) -> np.ndarray:
    nx, ny = source_field.shape
    pad_x = nx * (pad_factor - 1) // 2
    pad_y = ny * (pad_factor - 1) // 2
    padded = np.pad(source_field, ((pad_x, pad_x), (pad_y, pad_y)), mode="constant")
    spectrum = np.fft.fftshift(np.fft.fft2(np.fft.ifftshift(padded)))
    propagated = np.fft.fftshift(np.fft.ifft2(np.fft.ifftshift(spectrum * h_forward)))
    return propagated[pad_x : pad_x + nx, pad_y : pad_y + ny]


def optimize_phase(input_path: Path, output_path: Path, epochs: int, lr: float) -> None:
    data = sio.loadmat(input_path, squeeze_me=False, struct_as_record=False)
    target = data["target"][0, 0]
    cfg = data["cfg"][0, 0]

    target_amp = normalize_map(np.asarray(target.amp, dtype=np.float32))
    target_mask = np.asarray(target.mask, dtype=bool)
    source_mask = np.asarray(target.source_mask, dtype=bool)
    dark_mask = ~target_mask
    target_smooth = normalize_map(scipy.ndimage.gaussian_filter(target_amp, 1.0))

    rng = np.random.default_rng(int(matlab_scalar(cfg, "rng_seed")))
    pad_factor = int(matlab_scalar(cfg, "pad_factor"))
    h_forward = build_asm_kernel(cfg)
    h_backward = np.conj(h_forward)

    phase = rng.uniform(0.0, TWO_PI, size=target_amp.shape).astype(np.float32)
    phase[~source_mask] = 0.0
    target_weight = 0.04 + target_smooth
    target_weight[dark_mask] = 0.02

    loss_history = np.zeros((epochs, 5), dtype=np.float32)
    best_loss = float("inf")
    best_phase = phase.copy()
    best_amp = np.zeros_like(target_amp)

    relax = max(0.05, min(float(lr), 1.0))
    for epoch in range(epochs):
        source_field = np.exp(1j * phase) * source_mask
        focus_field = propagate_asm(source_field, h_forward, pad_factor)
        pred_amp = normalize_map(np.abs(focus_field))
        pred_smooth = normalize_map(scipy.ndimage.gaussian_filter(pred_amp, 0.8))

        pcc = pearson_score(pred_smooth, target_smooth)
        weighted_mse = float(np.mean((1.0 + 5.0 * target_mask + 8.0 * dark_mask) * (pred_smooth - target_smooth) ** 2))
        target_values = pred_amp[target_mask]
        dark_values = pred_amp[dark_mask]
        uniformity = float(np.var(target_values)) if target_values.size > 4 else 0.0
        dark_penalty = float(np.mean(dark_values**2))
        energy_efficiency = float(np.sum((pred_amp**2) * target_mask) / (np.sum(pred_amp**2) + 1e-12))
        loss = (1.0 - pcc) + 2.5 * weighted_mse + 1.4 * uniformity + 1.2 * dark_penalty + 0.8 * (1.0 - energy_efficiency)

        if loss < best_loss:
            best_loss = loss
            best_phase = phase.copy()
            best_amp = pred_amp.copy()

        constrained_focus = target_weight * np.exp(1j * np.angle(focus_field))
        padded_focus = np.pad(
            constrained_focus,
            (
                (target_amp.shape[0] * (pad_factor - 1) // 2, target_amp.shape[0] * (pad_factor - 1) // 2),
                (target_amp.shape[1] * (pad_factor - 1) // 2, target_amp.shape[1] * (pad_factor - 1) // 2),
            ),
            mode="constant",
        )
        target_spectrum = np.fft.fftshift(np.fft.fft2(np.fft.ifftshift(padded_focus)))
        source_back = np.fft.fftshift(np.fft.ifft2(np.fft.ifftshift(target_spectrum * h_backward)))
        pad_x = target_amp.shape[0] * (pad_factor - 1) // 2
        pad_y = target_amp.shape[1] * (pad_factor - 1) // 2
        phase_candidate = np.angle(source_back[pad_x : pad_x + target_amp.shape[0], pad_y : pad_y + target_amp.shape[1]])
        blended = (1.0 - relax) * np.exp(1j * phase) + relax * np.exp(1j * phase_candidate)
        phase = np.mod(np.angle(blended), TWO_PI)
        phase[~source_mask] = 0.0

        loss_history[epoch, :] = [loss, pcc, weighted_mse, uniformity, energy_efficiency]
        if (epoch + 1) % 100 == 0 or epoch == 0:
            print(
                f"[python] epoch {epoch + 1:5d}/{epochs} | loss {loss:.5f} "
                f"| pcc {pcc:.4f} | ee {energy_efficiency * 100:.2f}%"
            )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sio.savemat(
        output_path,
        {
            "phase_python": best_phase.astype(np.float32),
            "python_asm_amp": best_amp.astype(np.float32),
            "python_loss_history": loss_history,
            "best_loss": np.array([[best_loss]], dtype=np.float32),
        },
    )
    print(f"[python] wrote: {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Optimize a continuous initial phase map for the HDSP A target.")
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--epochs", type=int, default=2500)
    parser.add_argument("--lr", type=float, default=0.35)
    args = parser.parse_args()
    optimize_phase(args.input, args.output, args.epochs, args.lr)


if __name__ == "__main__":
    main()
