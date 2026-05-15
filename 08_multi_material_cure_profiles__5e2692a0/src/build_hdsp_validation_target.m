function target = build_hdsp_validation_target(Nx, Lx)
if nargin < 1
    Nx = 512;
end
if nargin < 2
    Lx = 65e-3;
end

dx = Lx / Nx;
x = (-Nx/2 : Nx/2-1) * dx;
[Y_grid, X_grid] = meshgrid(x, x);

strut_width = 1.0e-3;
pore_size = 3.0e-3;
pitch = strut_width + pore_size;
mask_X = mod(X_grid + pitch / 2, pitch) < strut_width;
mask_Y = mod(Y_grid + pitch / 2, pitch) < strut_width;
scaffold_raw = mask_X | mask_Y;

target_radius = 15e-3;
circle_mask = (X_grid.^2 + Y_grid.^2) <= target_radius^2;
imag_target_raw = scaffold_raw & circle_mask;
imag_target = imgaussfilt(double(imag_target_raw), 0.5);
imag_target = imag_target / max(imag_target(:));
target_mask = imag_target > 0.5;

target = struct();
target.Nx = Nx;
target.Lx = Lx;
target.dx = dx;
target.x = x;
target.X_grid = X_grid;
target.Y_grid = Y_grid;
target.raw = imag_target_raw;
target.image = imag_target;
target.mask = target_mask;
target.roi_pixels = nnz(target_mask);
end
