function focus_amp = compute_asm_focus_field(phase_map, aperture_mask, Nx, Ny, H_forward)
pad_factor = size(H_forward, 1) / Nx;
Nx_pad = Nx * pad_factor;
Ny_pad = Ny * pad_factor;

U_source = zeros(Nx_pad, Ny_pad);
center_source = exp(1i * phase_map);
center_source(~aperture_mask) = 0;
U_source(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = center_source;

A_source = fftshift(fft2(ifftshift(U_source)));
U_target = fftshift(ifft2(ifftshift(A_source .* H_forward)));
focus_field = U_target(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny);
focus_amp = abs(focus_field);
end
