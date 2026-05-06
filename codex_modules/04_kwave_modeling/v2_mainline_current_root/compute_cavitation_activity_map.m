function cav = compute_cavitation_activity_map(p_amp, params)
arguments
    p_amp
    params struct
end

p_amp = double(p_amp);
mask = true(size(p_amp));
if isfield(params, 'mask') && ~isempty(params.mask)
    mask = logical(params.mask);
end

pressure_on = get_param(params, 'pressure_on', 1.8e6);
pressure_full = get_param(params, 'pressure_full', 2.2e6);
pressure_stream = get_param(params, 'pressure_stream', 2.7e6);
pressure_damage = get_param(params, 'pressure_damage', 3.2e6);
saturation_shape = get_param(params, 'saturation_shape', 4.0);
trigger_sharpness = get_param(params, 'trigger_sharpness', 3.0);
streaming_penalty_strength = get_param(params, 'streaming_penalty_strength', 0.75);
streaming_penalty_power = get_param(params, 'streaming_penalty_power', 1.5);
smooth_sigma_px = get_param(params, 'smooth_sigma_px', 0.0);

activation = clamp01((p_amp - pressure_on) ./ max(pressure_full - pressure_on, eps));
penalty_drive = clamp01((p_amp - pressure_stream) ./ max(pressure_damage - pressure_stream, eps));

sat_norm = 1 - exp(-max(saturation_shape, eps));
saturation = (1 - exp(-max(saturation_shape, eps) .* activation)) ./ max(sat_norm, eps);
penalty = streaming_penalty_strength .* (penalty_drive .^ streaming_penalty_power);
penalty = clamp01(penalty);

trigger = (activation .^ max(trigger_sharpness, 1.0)) .* (1 - penalty);
growth = saturation .* (1 - penalty);
activity = max(growth, 0);
trigger = max(trigger, 0);
growth = max(growth, 0);

activation(~mask) = 0;
saturation(~mask) = 0;
penalty(~mask) = 0;
trigger(~mask) = 0;
growth(~mask) = 0;
activity(~mask) = 0;

if smooth_sigma_px > 0
    if ismatrix(activity)
        activity = imgaussfilt(activity, smooth_sigma_px);
    elseif ndims(activity) == 3
        activity = imgaussfilt3(activity, smooth_sigma_px);
    end
    trigger = activity .* (trigger ./ max(growth, eps));
    trigger(~isfinite(trigger)) = 0;
    growth = activity;
    trigger = min(max(trigger, 0), growth);
    activity(~mask) = 0;
    trigger(~mask) = 0;
    growth(~mask) = 0;
end

cav = struct();
cav.activation = activation;
cav.saturation = saturation;
cav.penalty = penalty;
cav.trigger = trigger;
cav.growth = growth;
cav.activity = activity;
cav.pressure_on = pressure_on;
cav.pressure_full = pressure_full;
cav.pressure_stream = pressure_stream;
cav.pressure_damage = pressure_damage;
end

function value = get_param(params, field_name, default_value)
if isfield(params, field_name)
    value = params.(field_name);
else
    value = default_value;
end
end

function y = clamp01(x)
y = min(max(x, 0), 1);
end
