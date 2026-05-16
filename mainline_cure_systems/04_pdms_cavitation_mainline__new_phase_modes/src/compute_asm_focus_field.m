function focus = compute_asm_focus_field(phase_map, source_mask, propagator)
%COMPUTE_ASM_FOCUS_FIELD Propagate one source phase map to the target plane.
source_field = exp(1i * wrap_phase(phase_map));
source_field(~source_mask) = 0;

padded_source = zeros(propagator.Nx_pad, propagator.Ny_pad);
padded_source(propagator.center_idx, propagator.center_idx) = source_field;

source_spectrum = fftshift(fft2(ifftshift(padded_source)));
target_field = fftshift(ifft2(ifftshift(source_spectrum .* propagator.H_forward)));
field_crop = target_field(propagator.center_idx, propagator.center_idx);

focus.field = field_crop;
focus.amp = abs(field_crop);
focus.amp_norm = focus.amp / (max(focus.amp(:)) + eps);
focus.phase = angle(field_crop);
end
