function ctx = target_grid_scaffold_circle_current(ctx)
params = ctx.params;
x = linspace(-params.Lx / 2, params.Lx / 2, params.Nx);
[X, Y] = ndgrid(x, x);
pitch = 4e-3;
strut_width = 0.9e-3;
grid_mask = mod(X + pitch / 2, pitch) < strut_width | mod(Y + pitch / 2, pitch) < strut_width;
circle_mask = X.^2 + Y.^2 <= (0.82 * params.aperture_radius)^2;
raw = grid_mask & circle_mask;
amp = imgaussfilt(double(raw), 0.5);
amp = hdsp_normalize01(amp);
ctx.target = struct();
ctx.target.name = 'grid_scaffold_circle_current';
ctx.target.amp = amp;
ctx.target.design_amp = amp;
ctx.target.mask = amp > 0.5;
ctx.target.source_mask = hdsp_source_aperture(params);
end

