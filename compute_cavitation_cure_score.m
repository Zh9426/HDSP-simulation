function [cure_score, cured_mask, components] = compute_cavitation_cure_score( ...
    cavitation_dose, thermal_dose, penalty, params)
arguments
    cavitation_dose
    thermal_dose
    penalty
    params struct
end

thermal_weight = get_param(params, 'thermal_weight', 0.15);
penalty_weight = get_param(params, 'penalty_weight', 0.6);
threshold = get_param(params, 'threshold', 1.0);

cavitation_dose = double(cavitation_dose);
thermal_dose = double(thermal_dose);
penalty = double(penalty);

thermal_contribution = thermal_weight .* thermal_dose;
penalty_contribution = penalty_weight .* penalty;
cure_score = cavitation_dose + thermal_contribution - penalty_contribution;
cure_score = max(cure_score, 0);
cured_mask = cure_score >= threshold;

components = struct();
components.cavitation_dose = cavitation_dose;
components.thermal_dose = thermal_dose;
components.thermal_contribution = thermal_contribution;
components.penalty = penalty;
components.penalty_contribution = penalty_contribution;
components.threshold = threshold;
end

function value = get_param(params, field_name, default_value)
if isfield(params, field_name)
    value = params.(field_name);
else
    value = default_value;
end
end
