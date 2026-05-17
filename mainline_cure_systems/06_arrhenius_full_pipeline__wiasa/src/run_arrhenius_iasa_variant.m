function result = run_arrhenius_iasa_variant(phase_method, target_amp_design, source_mask, H_forward, H_backward, phase_step, min_base_layers, iasa_epoch, iasa_anchor_eta)
%RUN_ARRHENIUS_IASA_VARIANT WIASA: GS propagation with multiplicative target weighting.
if ~strcmpi(strtrim(phase_method), 'wiasa')
    error('This flow is the WIASA variant. phase_method must be ''wiasa''.');
end

[Nx, Ny] = size(target_amp_design);
Nx_pad = size(H_forward, 1);
Ny_pad = size(H_forward, 2);
center_idx = Nx/2+1:Nx/2+Nx;

rng(9426);
seed_phase = zeros(Nx, Ny);
seed_phase(source_mask) = 2 * pi * rand(nnz(source_mask), 1) - pi;
current_phase = seed_phase;
phase_anchor = seed_phase;

target_pad = zeros(Nx_pad, Ny_pad);
target_pad(center_idx, center_idx) = target_amp_design;
mask_line = false(Nx_pad, Ny_pad);
mask_line(center_idx, center_idx) = target_amp_design > 0.45;
weight_pad = 0.05 + target_pad * 1.95;

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

    if epoch > 5
        beta = 0.6;
        correction = (target_pad(mask_line) ./ (rec_amp_norm(mask_line) + 1e-6)) .^ beta;
        weight_pad(mask_line) = weight_pad(mask_line) .* correction;
        weight_pad(weight_pad > 10) = 10;
    end

    U_target_constrained = weight_pad .* exp(1i * angle(U_target));
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

% WIASA still constructs the phase plate only after the weighted phase loop.
[initial_phase, ~] = project_phase_to_board(seed_phase, phase_step, min_base_layers, source_mask, 0, true);
[final_phase, net_num_board] = project_phase_to_board(current_phase, phase_step, min_base_layers, source_mask, 0, true);

result.initial_label = 'WIASA seed';
result.final_label = 'WIASA';
result.initial_phase = initial_phase;
result.final_phase = final_phase;
result.net_num_board = net_num_board;
result.initial_amp = compute_asm_focus_field(initial_phase, source_mask, Nx, Ny, H_forward);
result.final_amp = compute_asm_focus_field(final_phase, source_mask, Nx, Ny, H_forward);
end
