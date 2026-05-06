function target = build_a_phase_target(cfg)
%BUILD_A_PHASE_TARGET Build the A-shaped pressure-amplitude target.
x = (-cfg.Nx/2:cfg.Nx/2-1) * cfg.dx;
y = (-cfg.Ny/2:cfg.Ny/2-1) * cfg.dy;
[Y, X] = meshgrid(y, x);

half_width = cfg.a_width / 2;
height = cfg.a_height;
base_y = -height / 2;
top_y = height / 2;
left_base = [-cfg.a_base_width / 2, base_y];
right_base = [cfg.a_base_width / 2, base_y];
apex = [0, top_y];
bar_left = [-cfg.a_bar_width / 2, cfg.a_bar_y];
bar_right = [cfg.a_bar_width / 2, cfg.a_bar_y];

left_leg = distance_to_segment(X, Y, left_base, apex) <= half_width;
right_leg = distance_to_segment(X, Y, right_base, apex) <= half_width;
cross_bar = distance_to_segment(X, Y, bar_left, bar_right) <= half_width;
raw_mask = left_leg | right_leg | cross_bar;
aperture_clip = X.^2 + Y.^2 <= cfg.target_radius^2;
raw_mask = raw_mask & aperture_clip;

amp = imgaussfilt(double(raw_mask), cfg.target_blur_sigma_px);
amp = amp / (max(amp(:)) + eps);

source_mask = X.^2 + Y.^2 <= cfg.source_radius^2;

target.x = x;
target.y = y;
target.X = X;
target.Y = Y;
target.amp = amp;
target.mask = amp >= cfg.target_mask_threshold;
target.source_mask = source_mask;
end

function dist = distance_to_segment(X, Y, p0, p1)
vx = p1(1) - p0(1);
vy = p1(2) - p0(2);
wx = X - p0(1);
wy = Y - p0(2);
seg_len_sq = vx^2 + vy^2;
t = (wx * vx + wy * vy) / seg_len_sq;
t = min(max(t, 0), 1);
closest_x = p0(1) + t * vx;
closest_y = p0(2) + t * vy;
dist = sqrt((X - closest_x).^2 + (Y - closest_y).^2);
end
