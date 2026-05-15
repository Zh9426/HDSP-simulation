function [dose_rate, components] = compute_cavitation_dose_rate(trigger, growth, params)
arguments
    trigger
    growth
    params struct
end

growth_floor = get_param(params, 'dose_growth_floor', 0.60);
trigger_weight = get_param(params, 'dose_trigger_weight', 0.40);
cloud_radius_px = round(get_param(params, 'dose_cloud_radius_px', 0));
cloud_floor = get_param(params, 'dose_cloud_floor', 1.0);
cloud_power = get_param(params, 'dose_cloud_power', 1.0);
cloud_weight = get_param(params, 'dose_cloud_weight', 1.0);
seed_floor = get_param(params, 'dose_seed_floor', 1.0);
seed_power = get_param(params, 'dose_seed_power', 1.0);
fill_radius_px = round(get_param(params, 'dose_fill_radius_px', 0));
fill_weight = get_param(params, 'dose_fill_weight', 0.0);
fill_growth_ref = get_param(params, 'dose_fill_growth_ref', 0.20);
fill_power = get_param(params, 'dose_fill_power', 1.0);

trigger = double(trigger);
growth = double(growth);

base_drive = growth .* (growth_floor + trigger_weight .* trigger);
cloud_support = compute_local_cloud_support(growth, cloud_radius_px);
cloud_gate = cloud_floor + (1 - cloud_floor) .* (cloud_support .^ max(cloud_power, eps));
cloud_gate = 1 - min(max(cloud_weight, 0), 1) .* (1 - cloud_gate);
seed_gate = seed_floor + (1 - seed_floor) .* (trigger .^ max(seed_power, eps));
coherent_rate = base_drive .* cloud_gate .* seed_gate;
dose_rate = coherent_rate;
fill_rate = zeros(size(coherent_rate), 'like', coherent_rate);
if fill_weight > 0 && fill_radius_px > 0
    neighbor_rate = compute_local_cloud_support(coherent_rate, fill_radius_px);
    fill_gate = min(max(growth ./ max(fill_growth_ref, eps), 0), 1) .^ max(fill_power, eps);
    fill_rate = fill_weight .* neighbor_rate .* fill_gate;
    dose_rate = max(dose_rate, fill_rate);
end
dose_rate = min(max(dose_rate, 0), 1);

components = struct();
components.base_drive = base_drive;
components.cloud_support = cloud_support;
components.cloud_gate = cloud_gate;
components.seed_gate = seed_gate;
components.coherent_rate = coherent_rate;
components.fill_rate = fill_rate;
components.fill_gain = max(dose_rate - coherent_rate, 0);
end

function support = compute_local_cloud_support(growth, radius_px)
if radius_px <= 0
    support = ones(size(growth), 'like', growth);
    return;
end

kernel_size = 2 * radius_px + 1;
if ismatrix(growth)
    kernel = ones(kernel_size, kernel_size, 'like', growth) ./ (kernel_size ^ 2);
    support = conv2(growth, kernel, 'same');
else
    kernel = ones(kernel_size, kernel_size, kernel_size, 'like', growth) ./ (kernel_size ^ 3);
    support = convn(growth, kernel, 'same');
end
support = min(max(support, 0), 1);
end

function value = get_param(params, field_name, default_value)
if isfield(params, field_name)
    value = params.(field_name);
else
    value = default_value;
end
end
