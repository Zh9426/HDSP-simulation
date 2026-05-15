function [conductivity_multiplier, absorption_multiplier, reaction_multiplier] = ...
    compute_cure_feedback_terms(params, chi_focal, cavitation_trigger, cavitation_growth)
arguments
    params struct
    chi_focal
    cavitation_trigger
    cavitation_growth
end

conductivity_gain = single(get_param(params, 'conductivity_gain', 0.2));
absorption_gain = single(get_param(params, 'absorption_gain', 0.5));
trigger_gain = single(get_param(params, 'trigger_gain', 4.0));
growth_gain = single(get_param(params, 'growth_gain', 0.0));

chi_focal = single(chi_focal);
cavitation_trigger = single(cavitation_trigger);
cavitation_growth = single(cavitation_growth);

conductivity_multiplier = 1 + conductivity_gain .* chi_focal;
absorption_multiplier = 1 + absorption_gain .* chi_focal;
reaction_multiplier = 1 ...
    + trigger_gain .* cavitation_trigger ...
    + growth_gain .* cavitation_growth;

conductivity_multiplier = max(conductivity_multiplier, 1);
absorption_multiplier = max(absorption_multiplier, 1);
reaction_multiplier = max(reaction_multiplier, 1);
end

function value = get_param(params, field_name, default_value)
if isfield(params, field_name)
    value = params.(field_name);
else
    value = default_value;
end
end
