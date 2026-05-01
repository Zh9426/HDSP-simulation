function cases = build_pressure_validation_cases(target_mask, params, dx)
arguments
    target_mask
    params struct
    dx (1, 1) double {mustBePositive}
end

target_mask = logical(target_mask);
target_pressure = get_param(params, 'validation_target_pressure', 2.25e6);
background_pressure = get_param(params, 'validation_background_pressure', 1.20e6);

cases = repmat(empty_case(), 1, 0);
cases(end + 1) = make_case( ...
    'ideal_binary', ...
    'Upper-bound binary pressure: high target, sub-onset background.', ...
    pressure_case(target_mask, target_pressure, background_pressure));

blurred_shape = imgaussfilt(double(target_mask), 1.5);
blurred_shape = normalize_unit(blurred_shape);
cases(end + 1) = make_case( ...
    'blurred_edge', ...
    'Finite acoustic transition around the target edge.', ...
    background_pressure + (target_pressure - background_pressure) .* blurred_shape);

leak_pressure = max(background_pressure, get_param(params, 'pressure_on', 1.72e6) - 0.04e6);
cases(end + 1) = make_case( ...
    'background_leakage', ...
    'Background sits just below cavitation onset.', ...
    pressure_case(target_mask, 2.18e6, leak_pressure));

cases(end + 1) = make_case( ...
    'speckle_nonuniform', ...
    'Deterministic nonuniformity inside target and weak background speckle.', ...
    speckle_pressure_case(target_mask, 2.05e6, background_pressure));

edge_pressure = edge_rolloff_pressure_case(target_mask, dx, target_pressure, 1.58e6, background_pressure);
cases(end + 1) = make_case( ...
    'target_edge_rolloff', ...
    'Target edge weakens toward the cavitation-onset regime.', ...
    edge_pressure);

hotspot_pressure = pressure_case(target_mask, 2.12e6, background_pressure);
hotspot_pressure = add_off_target_hotspot(hotspot_pressure, target_mask, dx, 2.25e6);
cases(end + 1) = make_case( ...
    'off_target_hotspot', ...
    'Localized off-target pressure lobe tests over-cure response.', ...
    hotspot_pressure);

cases(end + 1) = make_case( ...
    'target_overdrive', ...
    'Target pressure exceeds the streaming-risk range without changing the cure rule.', ...
    pressure_case(target_mask, 2.55e6, background_pressure));
end

function entry = empty_case()
entry = struct( ...
    'name', '', ...
    'description', '', ...
    'pressure_map', []);
end

function entry = make_case(name, description, pressure_map)
entry = empty_case();
entry.name = name;
entry.description = description;
entry.pressure_map = double(pressure_map);
end

function p_amp = pressure_case(target_mask, target_pressure, background_pressure)
p_amp = ones(size(target_mask)) .* background_pressure;
p_amp(target_mask) = target_pressure;
end

function p_amp = speckle_pressure_case(target_mask, target_pressure, background_pressure)
stream = RandStream('mt19937ar', 'Seed', 9426);
noise = randn(stream, size(target_mask));
noise = imgaussfilt(noise, 1.0);
noise = noise ./ max(abs(noise(:)) + eps);

p_amp = ones(size(target_mask)) .* background_pressure;
target_variation = 1.0 + 0.20 .* noise;
background_variation = 1.0 + 0.06 .* noise;
p_amp(target_mask) = target_pressure .* target_variation(target_mask);
p_amp(~target_mask) = background_pressure .* background_variation(~target_mask);
p_amp = min(max(p_amp, 0.9e6), 2.35e6);
end

function p_amp = edge_rolloff_pressure_case(target_mask, dx, center_pressure, edge_pressure, background_pressure)
edge_width_px = max(round(0.80e-3 / dx), 1);
distance_inside = bwdist(~target_mask);
edge_factor = min(distance_inside ./ edge_width_px, 1);

p_amp = ones(size(target_mask)) .* background_pressure;
p_amp(target_mask) = edge_pressure + (center_pressure - edge_pressure) .* edge_factor(target_mask);
end

function p_amp = add_off_target_hotspot(p_amp, target_mask, dx, hotspot_pressure)
[rows, cols] = size(target_mask);
[Y, X] = ndgrid(1:rows, 1:cols);
offset_px = round(6.0e-3 / dx);
sigma_px = max(round(1.3e-3 / dx), 1);
center_row = round(rows / 2);
center_col = min(cols, round(cols / 2) + offset_px);
hotspot = exp(-((Y - center_row).^2 + (X - center_col).^2) ./ (2 * sigma_px^2));
hotspot(target_mask) = 0;
background_level = min(p_amp(:));
p_amp = max(p_amp, background_level + (hotspot_pressure - background_level) .* hotspot);
end

function x = normalize_unit(x)
x = double(x);
max_x = max(x(:));
if max_x > 0
    x = x ./ max_x;
end
end

function value = get_param(params, field_name, default_value)
if isfield(params, field_name)
    value = params.(field_name);
else
    value = default_value;
end
end
