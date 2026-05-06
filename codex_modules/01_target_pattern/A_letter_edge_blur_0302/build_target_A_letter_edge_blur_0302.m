function target = build_target_A_letter_edge_blur_0302(Nx, Lx, opts)
%BUILD_TARGET_A_LETTER_EDGE_BLUR_0302 Build the 0302-era blurred A-letter target.
%
% This function extracts only the target-pattern logic from the historical
% HDSPdebug target section. It intentionally does not include IASA, phase-board,
% k-Wave, thermal, or cure logic.

if nargin < 1 || isempty(Nx)
    Nx = 384;
end
if nargin < 2 || isempty(Lx)
    Lx = 40e-3;
end
if nargin < 3 || isempty(opts)
    opts = struct();
end

opts = apply_defaults(opts, struct( ...
    'height_px', 160, ...
    'base_width_px', 100, ...
    'stroke_px', 22, ...
    'bar_pos_px', 50, ...
    'bar_width_px', 20, ...
    'smooth_sigma_px', 1.5));

Ny = Nx;
dx = Lx / Nx;
x = (-Nx/2 : Nx/2-1) * dx;

cx = round(Nx / 2);
cy = round(Ny / 2);
x_top = cx - opts.height_px / 2;
x_bottom = cx + opts.height_px / 2;
slope = opts.height_px / (opts.base_width_px / 2);

[Y_grid_px, X_grid_px] = meshgrid(1:Ny, 1:Nx);
dx_outer = X_grid_px - x_top;
dy_abs = abs(Y_grid_px - cy);
width_at_x = dx_outer / slope;
mask_outer = (dx_outer >= 0) & (dx_outer <= opts.height_px) & (dy_abs <= width_at_x);

x_top_inner = x_top + opts.stroke_px * 1.8;
dx_inner = X_grid_px - x_top_inner;
width_inner_at_x = dx_inner / slope;
mask_inner_cone = (dx_inner >= 0) & (dy_abs <= width_inner_at_x);

x_bar_start = x_bottom - opts.bar_pos_px - opts.bar_width_px / 2;
x_bar_end = x_bottom - opts.bar_pos_px + opts.bar_width_px / 2;
mask_bar = (X_grid_px >= x_bar_start) & (X_grid_px <= x_bar_end);

raw_mask = mask_outer & (~mask_inner_cone | mask_bar);
image = imgaussfilt(double(raw_mask), opts.smooth_sigma_px);
if max(image(:)) > 0
    image = image / max(image(:));
end

target = struct();
target.name = 'A_letter_edge_blur_0302';
target.Nx = Nx;
target.Ny = Ny;
target.Lx = Lx;
target.dx = dx;
target.x = x;
target.X_grid_px = X_grid_px;
target.Y_grid_px = Y_grid_px;
target.raw = raw_mask;
target.image = image;
target.mask = image > 0.5;
target.roi_pixels = nnz(target.mask);
target.options = opts;
end

function opts = apply_defaults(opts, defaults)
fields = fieldnames(defaults);
for idx = 1:numel(fields)
    name = fields{idx};
    if ~isfield(opts, name) || isempty(opts.(name))
        opts.(name) = defaults.(name);
    end
end
end
