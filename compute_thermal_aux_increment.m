function increment = compute_thermal_aux_increment(bulk_temp_rise, dt, is_exposure, params)
arguments
    bulk_temp_rise
    dt (1, 1) double
    is_exposure (1, 1) logical
    params struct
end

thermal_delta_ref = get_param(params, 'thermal_delta_ref', 20.0);
thermal_dose_time = get_param(params, 'thermal_dose_time', 0.12);
cooling_thermal_weight = get_param(params, 'cooling_thermal_weight', 0.15);

bulk_temp_rise = max(bulk_temp_rise, 0);
phase_weight = 1.0;
if ~is_exposure
    phase_weight = cooling_thermal_weight;
end

increment = bulk_temp_rise ./ thermal_delta_ref .* (dt ./ thermal_dose_time) .* phase_weight;
end

function value = get_param(params, field_name, default_value)
if isfield(params, field_name)
    value = params.(field_name);
else
    value = default_value;
end
end
