function result = run_arrhenius_iasa_variant(phase_method, target_amp_design, source_mask, H_forward, H_backward, phase_step, min_base_layers, iasa_epoch, iasa_anchor_eta)
%RUN_ARRHENIUS_IASA_VARIANT Classical GS: propagate, constrain target amplitude, back-propagate.
if ~strcmpi(strtrim(phase_method), 'gs')
    error('This flow is the GS variant. phase_method must be ''gs''.');
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

for epoch = 1:iasa_epoch
    U_source = zeros(Nx_pad, Ny_pad);
    center_source = exp(1i * current_phase);
    center_source(~source_mask) = 0;
    U_source(center_idx, center_idx) = center_source;

    A_source = fftshift(fft2(ifftshift(U_source)));
    U_target = fftshift(ifft2(ifftshift(A_source .* H_forward)));

    U_target_constrained = target_pad .* exp(1i * angle(U_target));
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

% The phase plate is constructed only after GS convergence.
[initial_phase, ~] = project_phase_to_board(seed_phase, phase_step, min_base_layers, source_mask, 0, true);
[final_phase, net_num_board] = project_phase_to_board(current_phase, phase_step, min_base_layers, source_mask, 0, true);

result.initial_label = 'GS seed';
result.final_label = 'GS';
result.initial_phase = initial_phase;
result.final_phase = final_phase;
result.net_num_board = net_num_board;
result.initial_amp = compute_asm_focus_field(initial_phase, source_mask, Nx, Ny, H_forward);
result.final_amp = compute_asm_focus_field(final_phase, source_mask, Nx, Ny, H_forward);
end
