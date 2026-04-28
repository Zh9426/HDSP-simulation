function dose_rate = compute_cavitation_dose_rate(trigger, growth, params)
arguments
    trigger
    growth
    params struct
end

growth_floor = get_param(params, 'dose_growth_floor', 0.60);
trigger_weight = get_param(params, 'dose_trigger_weight', 0.40);

trigger = double(trigger);
growth = double(growth);

dose_rate = growth .* (growth_floor + trigger_weight .* trigger);
dose_rate = min(max(dose_rate, 0), 1);
end

function value = get_param(params, field_name, default_value)
if isfield(params, field_name)
    value = params.(field_name);
else
    value = default_value;
end
end
