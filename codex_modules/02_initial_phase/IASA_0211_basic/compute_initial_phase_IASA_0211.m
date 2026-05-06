function result = compute_initial_phase_IASA_0211(target_image, params)
%COMPUTE_INITIAL_PHASE_IASA_0211 Compute a 0211-era padded IASA phase.
%
% This function keeps only the initial-phase computation from the historical
% IASAdebug.m script. Target construction, phase-board mapping, k-Wave, and
% curing are intentionally outside this module.

if nargin < 2 || isempty(params)
    params = struct();
end

params = apply_defaults(params, struct( ...
    'Lx', 40e-3, ...
    'lambda', 1480 / 4.0e6, ...
    'z_target_dist', 20e-3, ...
    'pad_factor', 2, ...
    'epoch', 150, ...
    'seed', 9426, ...
    'weight_gain', 1.5, ...
    'feedback_beta', 0.8, ...
    'max_weight', 10));

[Nx, Ny] = size(target_image);
if Nx ~= Ny
    error('target_image must be square for this historical IASA implementation.');
end

target_image = double(target_image);
target_image = target_image ./ max(max(target_image(:)), eps);

Nx_pad = Nx * params.pad_factor;
Ny_pad = Ny * params.pad_factor;
Lx_pad = params.Lx * params.pad_factor;
dk_pad = 2 * pi / Lx_pad;
kx_pad = (-Nx_pad/2 : Nx_pad/2-1) * dk_pad;
[Kx_pad, Ky_pad] = meshgrid(kx_pad, kx_pad);

k_water = 2 * pi / params.lambda;
Kz_sq = k_water^2 - Kx_pad.^2 - Ky_pad.^2;
Kz_sq(Kz_sq < 0) = 0;
H_forward = exp(1i * sqrt(Kz_sq) * params.z_target_dist);
H_backward = exp(-1i * sqrt(Kz_sq) * params.z_target_dist);

rng(params.seed);
center_rows = Nx/2+1:Nx/2+Nx;
center_cols = Ny/2+1:Ny/2+Ny;

board_phase_pad = zeros(Nx_pad, Ny_pad);
board_phase_pad(center_rows, center_cols) = exp(1i * rand(Nx, Ny) * 2 * pi);

target_pad = zeros(Nx_pad, Ny_pad);
target_pad(center_rows, center_cols) = target_image;
weight_pad = target_pad * params.weight_gain;
mask_roi = target_pad > 0.5;
mask_dark = target_pad < 0.5;

for iter = 1:params.epoch
    source_field = zeros(Nx_pad, Ny_pad);
    center_phase = angle(board_phase_pad(center_rows, center_cols));
    source_field(center_rows, center_cols) = exp(1i * center_phase);

    source_spectrum = fftshift(fft2(ifftshift(source_field)));
    target_field = fftshift(ifft2(ifftshift(source_spectrum .* H_forward)));

    rec_amp = abs(target_field);
    peak_val = max(rec_amp(mask_roi));
    if peak_val == 0
        peak_val = max(rec_amp(:));
    end
    rec_amp_norm = rec_amp / max(peak_val, eps);

    if iter > 5
        correction = (target_pad(mask_roi) ./ (rec_amp_norm(mask_roi) + 1e-6)) .^ params.feedback_beta;
        weight_pad(mask_roi) = weight_pad(mask_roi) .* correction;
        weight_pad(weight_pad > params.max_weight) = params.max_weight;
        weight_pad(mask_dark) = 0;
    end

    target_constrained = weight_pad .* exp(1i * angle(target_field));
    target_spectrum = fftshift(fft2(ifftshift(target_constrained)));
    source_back = fftshift(ifft2(ifftshift(target_spectrum .* H_backward)));
    board_phase_pad = source_back;
end

phase = angle(board_phase_pad(center_rows, center_cols));

result = struct();
result.name = 'IASA_0211_basic';
result.phase = phase;
result.final_weight = weight_pad(center_rows, center_cols);
result.params = params;
end

function params = apply_defaults(params, defaults)
fields = fieldnames(defaults);
for idx = 1:numel(fields)
    name = fields{idx};
    if ~isfield(params, name) || isempty(params.(name))
        params.(name) = defaults.(name);
    end
end
end
