function result = run_arrhenius_iasa_variant(phase_method, target_amp_design, source_mask, H_forward, H_backward, phase_step, min_base_layers, iasa_epoch, iasa_anchor_eta)
%RUN_ARRHENIUS_IASA_VARIANT Build a pure-IASA initial phase for the Arrhenius mainline.
mode_now = lower(strtrim(phase_method));
valid_modes = {'gs', 'wiasa', 'biasa'};
if ~any(strcmp(mode_now, valid_modes))
    error('Unsupported phase_method: %s', phase_method);
end

[Nx, Ny] = size(target_amp_design);
Nx_pad = size(H_forward, 1);
Ny_pad = size(H_forward, 2);
center_idx = Nx/2+1:Nx/2+Nx;

rng(9426);
seed_phase = zeros(Nx, Ny);
seed_phase(source_mask) = 2 * pi * rand(nnz(source_mask), 1) - pi;

target_pad = zeros(Nx_pad, Ny_pad);
target_pad(center_idx, center_idx) = target_amp_design;
mask_line = false(Nx_pad, Ny_pad);
mask_halo = false(Nx_pad, Ny_pad);
mask_line(center_idx, center_idx) = target_amp_design > 0.45;
mask_halo(center_idx, center_idx) = imgaussfilt(double(target_amp_design > 0.45), 1.0) > 0.08 & ~(target_amp_design > 0.45);
mask_dark = ~(mask_line | mask_halo);

switch mode_now
    case 'biasa'
        result = run_biasa(seed_phase, target_pad, mask_line, mask_halo, mask_dark, source_mask, ...
            H_forward, H_backward, phase_step, min_base_layers, iasa_epoch, iasa_anchor_eta, center_idx);
        result.initial_label = 'BIASA seed';
        result.final_label = 'BIASA';
    case 'wiasa'
        result = run_continuous(seed_phase, target_pad, mask_line, source_mask, ...
            H_forward, H_backward, phase_step, min_base_layers, iasa_epoch, iasa_anchor_eta, center_idx, true);
        result.initial_label = 'WIASA seed';
        result.final_label = 'WIASA';
    case 'gs'
        result = run_continuous(seed_phase, target_pad, mask_line, source_mask, ...
            H_forward, H_backward, phase_step, min_base_layers, iasa_epoch, iasa_anchor_eta, center_idx, false);
        result.initial_label = 'GS seed';
        result.final_label = 'GS';
end

result.initial_amp = compute_asm_focus_field(result.initial_phase, source_mask, Nx, Ny, H_forward);
result.final_amp = compute_asm_focus_field(result.final_phase, source_mask, Nx, Ny, H_forward);
end

function result = run_continuous(seed_phase, target_pad, mask_line, source_mask, H_forward, H_backward, phase_step, min_base_layers, iasa_epoch, iasa_anchor_eta, center_idx, use_weighting)
[Nx_pad, Ny_pad] = size(H_forward);
current_phase = seed_phase;
phase_anchor = seed_phase;
weight_pad = ones(size(target_pad));
if use_weighting
    weight_pad = 0.05 + target_pad * 1.95;
end

for epoch = 1:iasa_epoch
    U_source = zeros(Nx_pad, Ny_pad);
    center_source = exp(1i * current_phase);
    center_source(~source_mask) = 0;
    U_source(center_idx, center_idx) = center_source;

    A_source = fftshift(fft2(ifftshift(U_source)));
    U_target = fftshift(ifft2(ifftshift(A_source .* H_forward)));
    rec_amp = abs(U_target);
    peak_val = max(rec_amp(mask_line));
    if peak_val == 0
        peak_val = max(rec_amp(:));
    end
    rec_amp_norm = rec_amp / (peak_val + eps);

    if use_weighting && epoch > 5
        beta = 0.6;
        correction = (target_pad(mask_line) ./ (rec_amp_norm(mask_line) + 1e-6)) .^ beta;
        weight_pad(mask_line) = weight_pad(mask_line) .* correction;
        weight_pad(weight_pad > 10) = 10;
    end

    if use_weighting
        constrained_amp = weight_pad;
    else
        constrained_amp = target_pad;
    end
    U_target_constrained = constrained_amp .* exp(1i * angle(U_target));
    A_target_cons = fftshift(fft2(ifftshift(U_target_constrained)));
    U_source_new = fftshift(ifft2(ifftshift(A_target_cons .* H_backward)));
    source_phase_candidate = angle(U_source_new(center_idx, center_idx));

    if iasa_anchor_eta < 1
        blended_complex = (1 - iasa_anchor_eta) .* exp(1i * phase_anchor) + ...
            iasa_anchor_eta .* exp(1i * source_phase_candidate);
        current_phase = angle(blended_complex);
    else
        current_phase = source_phase_candidate;
    end
    current_phase(~source_mask) = 0;
end

[final_phase, net_num_board] = project_phase_to_board(current_phase, phase_step, min_base_layers, source_mask, 0, true);
[initial_phase, ~] = project_phase_to_board(seed_phase, phase_step, min_base_layers, source_mask, 0, true);
result.initial_phase = initial_phase;
result.final_phase = final_phase;
result.net_num_board = net_num_board;
end

function result = run_biasa(seed_phase, target_pad, mask_line, mask_halo, mask_dark, source_mask, H_forward, H_backward, phase_step, min_base_layers, iasa_epoch, iasa_anchor_eta, center_idx)
[Nx_pad, Ny_pad] = size(H_forward);
phase_bias_seed = 0;
[phase_projected, net_num_board, phase_bias_seed] = project_phase_to_board( ...
    seed_phase, phase_step, min_base_layers, source_mask, phase_bias_seed, true);
phase_anchor = phase_projected;
weight_pad = 0.05 + target_pad * 1.95;

for epoch = 1:iasa_epoch
    U_source = zeros(Nx_pad, Ny_pad);
    center_source = exp(1i * phase_projected);
    center_source(~source_mask) = 0;
    U_source(center_idx, center_idx) = center_source;

    A_source = fftshift(fft2(ifftshift(U_source)));
    U_target = fftshift(ifft2(ifftshift(A_source .* H_forward)));
    rec_amp = abs(U_target);
    peak_val = max(rec_amp(mask_line));
    if peak_val == 0
        peak_val = max(rec_amp(:));
    end
    rec_amp_norm = rec_amp / (peak_val + eps);

    if epoch > 5
        beta = 0.6;
        correction = (target_pad(mask_line) ./ (rec_amp_norm(mask_line) + 1e-6)) .^ beta;
        weight_pad(mask_line) = weight_pad(mask_line) .* correction;
        weight_pad(weight_pad > 10) = 10;
        weight_pad(mask_halo) = 0.05;
        weight_pad(mask_dark) = 0;
    end

    U_target_constrained = weight_pad .* exp(1i * angle(U_target));
    A_target_cons = fftshift(fft2(ifftshift(U_target_constrained)));
    U_source_new = fftshift(ifft2(ifftshift(A_target_cons .* H_backward)));
    source_phase_candidate = angle(U_source_new(center_idx, center_idx));
    [phase_projected_raw, ~, phase_bias_seed] = project_phase_to_board( ...
        source_phase_candidate, phase_step, min_base_layers, source_mask, phase_bias_seed, true);

    if iasa_anchor_eta < 1
        blended_complex = (1 - iasa_anchor_eta) .* exp(1i * phase_anchor) + ...
            iasa_anchor_eta .* exp(1i * phase_projected_raw);
        blended_phase = angle(blended_complex);
    else
        blended_phase = phase_projected_raw;
    end

    [phase_projected, net_num_board, phase_bias_seed] = project_phase_to_board( ...
        blended_phase, phase_step, min_base_layers, source_mask, phase_bias_seed, true);
end

[initial_phase, ~] = project_phase_to_board(seed_phase, phase_step, min_base_layers, source_mask, 0, true);
result.initial_phase = initial_phase;
result.final_phase = phase_projected;
result.net_num_board = net_num_board;
end
