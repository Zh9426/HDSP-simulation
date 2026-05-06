function propagator = make_asm_propagator(cfg)
%MAKE_ASM_PROPAGATOR Build reusable angular-spectrum propagation kernels.
Nx_pad = cfg.Nx * cfg.pad_factor;
Ny_pad = cfg.Ny * cfg.pad_factor;
Lx_pad = cfg.Lx * cfg.pad_factor;
Ly_pad = cfg.Ly * cfg.pad_factor;

dkx = 2 * pi / Lx_pad;
dky = 2 * pi / Ly_pad;
kx = (-Nx_pad/2:Nx_pad/2-1) * dkx;
ky = (-Ny_pad/2:Ny_pad/2-1) * dky;
[Ky, Kx] = meshgrid(ky, kx);

k0 = 2 * pi * cfg.f0 / cfg.c_water;
Kz_sq = k0^2 - Kx.^2 - Ky.^2;
propagating = Kz_sq > 0;
Kz = zeros(size(Kz_sq));
Kz(propagating) = sqrt(Kz_sq(propagating));

H_forward = zeros(size(Kz_sq));
H_forward(propagating) = exp(1i * Kz(propagating) * cfg.z_target_dist);

propagator.Nx_pad = Nx_pad;
propagator.Ny_pad = Ny_pad;
propagator.H_forward = H_forward;
propagator.H_backward = conj(H_forward);
propagator.center_idx = cfg.Nx/2+1:cfg.Nx/2+cfg.Nx;
end
