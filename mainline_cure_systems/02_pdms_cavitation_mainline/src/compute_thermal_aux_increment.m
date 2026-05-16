function increment = compute_thermal_aux_increment(bulk_temp_rise, dt, is_exposure, params, cavitation_gate)
arguments
    bulk_temp_rise
    dt (1, 1) double
    is_exposure (1, 1) logical
    params struct
    cavitation_gate = []
end

thermal_delta_ref = get_param(params, 'thermal_delta_ref', 20.0);
thermal_dose_time = get_param(params, 'thermal_dose_time', 0.12);
cooling_thermal_weight = get_param(params, 'cooling_thermal_weight', 0.15);
gate_floor = get_param(params, 'thermal_cavitation_gate_floor', 1.0);
gate_power = get_param(params, 'thermal_cavitation_gate_power', 1.0);

bulk_temp_rise = max(bulk_temp_rise, 0);
phase_weight = 1.0;
if ~is_exposure
    phase_weight = cooling_thermal_weight;
end

increment = bulk_temp_rise ./ thermal_delta_ref .* (dt ./ thermal_dose_time) .* phase_weight;
if ~isempty(cavitation_gate)
    cavitation_gate = min(max(cavitation_gate, 0), 1);
    cavitation_gate = gate_floor + (1 - gate_floor) .* cavitation_gate .^ max(gate_power, eps);
    increment = increment .* cavitation_gate;
end
end

function value = get_param(params, field_name, default_value)
if isfield(params, field_name)
    value = params.(field_name);
else
    value = default_value;
end
end
