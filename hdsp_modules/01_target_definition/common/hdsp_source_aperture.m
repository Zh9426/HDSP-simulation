function mask = hdsp_source_aperture(params)
x = linspace(-params.Lx / 2, params.Lx / 2, params.Nx);
[X, Y] = ndgrid(x, x);
mask = X.^2 + Y.^2 <= params.aperture_radius^2;
end

