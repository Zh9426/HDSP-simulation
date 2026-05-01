function result = simulate_cure_from_pressure_map(p_amp, exposure_time, params, target_mask)
arguments
    p_amp
    exposure_time (1, 1) double {mustBeNonnegative}
    params struct
    target_mask = []
end

p_amp = double(p_amp);
cav = compute_cavitation_activity_map(p_amp, params);
[dose_rate, dose_components] = compute_cavitation_dose_rate( ...
    cav.trigger, cav.growth, params);

cavitation_dose_time = get_param(params, 'cavitation_dose_time', 0.04);
cavitation_dose = dose_rate .* (exposure_time ./ max(cavitation_dose_time, eps));
thermal_dose = resolve_thermal_dose(p_amp, exposure_time, params);

[cure_score, cured_mask, score_components] = compute_cavitation_cure_score( ...
    cavitation_dose, thermal_dose, cav.penalty, params);

result = struct();
result.cured_mask = cured_mask;
result.cure_score = cure_score;
result.cavitation = cav;
result.dose_rate = dose_rate;
result.dose_components = dose_components;
result.score_components = score_components;
result.exposure_time = exposure_time;
result.threshold = get_param(params, 'threshold', 1.0);

if ~isempty(target_mask)
    result.metrics = evaluate_cure_prediction(cure_score, target_mask, result.threshold);
end
end

function value = get_param(params, field_name, default_value)
if isfield(params, field_name)
    value = params.(field_name);
else
    value = default_value;
end
end

function thermal_dose = resolve_thermal_dose(p_amp, exposure_time, params)
if isfield(params, 'thermal_dose_map') && ~isempty(params.thermal_dose_map)
    thermal_dose = double(params.thermal_dose_map);
    return;
end

thermal_weight = get_param(params, 'thermal_weight', 0.0);
if thermal_weight <= 0
    thermal_dose = zeros(size(p_amp));
    return;
end

spatial_dx = get_param(params, 'spatial_dx', []);
if isempty(spatial_dx) || ~isscalar(spatial_dx) || ~isfinite(spatial_dx) || spatial_dx <= 0
    error('simulate_cure_from_pressure_map:MissingThermalInput', ...
        ['thermal_weight is enabled, so provide params.spatial_dx ', ...
        'or params.thermal_dose_map to keep the full cure model active.']);
end

thermal_dose = compute_thermal_aux_from_pressure_map( ...
    p_amp, exposure_time, params, spatial_dx);
end
