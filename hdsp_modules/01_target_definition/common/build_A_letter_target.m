function target = build_A_letter_target(params, smooth_sigma_px, mask_threshold, name)
x = linspace(-params.Lx / 2, params.Lx / 2, params.Nx);
[X, Y] = ndgrid(x, x);
height = 24e-3;
half_width = 8e-3;
bar_y = -2e-3;
bar_thickness = 2.2e-3;
dx_outer = X + height / 2;
width_at_x = half_width * max(1 - dx_outer / height, 0);
outer = dx_outer >= 0 & dx_outer <= height & abs(Y) <= width_at_x;
dx_inner = X + height / 2 - 5e-3;
inner_width = 0.56 * half_width * max(1 - dx_inner / (0.72 * height), 0);
inner = dx_inner >= 0 & abs(Y) <= inner_width;
bar = abs(X - bar_y) <= bar_thickness / 2 & abs(Y) <= 0.58 * half_width;
raw = outer & (~inner | bar);
if smooth_sigma_px > 0
    amp = imgaussfilt(double(raw), smooth_sigma_px);
else
    amp = double(raw);
end
amp = hdsp_normalize01(amp);
target = struct();
target.name = name;
target.amp = amp;
target.design_amp = amp;
target.mask = amp > mask_threshold;
target.source_mask = hdsp_source_aperture(params);
target.x = x;
target.y = x;
end

