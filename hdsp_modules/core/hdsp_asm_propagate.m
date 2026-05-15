function field = hdsp_asm_propagate(source_field, params, z_dist)
Nx = params.Nx;
Ny = params.Ny;
dx = params.dx;
dy = params.dy;
k = 2 * pi / params.lambda_water;
fx = (-Nx / 2:Nx / 2 - 1) / (Nx * dx);
fy = (-Ny / 2:Ny / 2 - 1) / (Ny * dy);
[Fx, Fy] = meshgrid(fy, fx);
Kx = 2 * pi * Fx;
Ky = 2 * pi * Fy;
Kz_sq = k^2 - Kx.^2 - Ky.^2;
H = zeros(Nx, Ny);
propagating = Kz_sq >= 0;
H(propagating) = exp(1i * sqrt(Kz_sq(propagating)) * z_dist);
spectrum = fftshift(fft2(ifftshift(source_field)));
field = fftshift(ifft2(ifftshift(spectrum .* H)));
end

