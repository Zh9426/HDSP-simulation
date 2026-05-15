function ctx = target_kou_frame_0209(ctx)
params = ctx.params;
Nx = params.Nx;
Ny = params.Ny;
[X, Y] = ndgrid(1:Nx, 1:Ny);
cx = round(Nx / 2);
cy = round(Ny / 2);
r_out = round(0.24 * Nx);
r_in = round(0.13 * Nx);
outer = abs(X - cx) <= r_out & abs(Y - cy) <= r_out;
inner = abs(X - cx) <= r_in & abs(Y - cy) <= r_in;
amp = double(outer & ~inner);
ctx.target = struct();
ctx.target.name = 'kou_frame_0209';
ctx.target.amp = amp;
ctx.target.design_amp = amp;
ctx.target.mask = amp > 0.5;
ctx.target.source_mask = hdsp_source_aperture(params);
end

