function [gel_dose, temperature_C, components] = compute_sonothermal_gel_dose_from_pressure_map( ...
    p_amp, exposure_time, params, dx)
arguments
    p_amp
    exposure_time (1, 1) double {mustBeNonnegative}
    params struct
    dx (1, 1) double {mustBePositive}
end

p_amp = double(p_amp);
ambient_temp_C = get_param(params, 'ambient_temp_C', 25.0);
pressure_ref = get_param(params, 'thermal_pressure_ref', 2.25e6);
peak_deltaT_ref = get_param(params, 'thermal_peak_deltaT', 30.0);
exposure_ref = get_param(params, 'thermal_exposure_ref', 0.60);
thermal_diffusivity = get_param(params, 'thermal_diffusivity', 1.0e-7);
thermal_blur_scale = get_param(params, 'thermal_blur_scale', 1.0);
self_enhancing = get_param(params, 'self_enhancing_absorption', false);

base_heat = (p_amp ./ max(pressure_ref, eps)).^2 ...
    .* (exposure_time ./ max(exposure_ref, eps));
absorption_gain = ones(size(base_heat));

temperature_C = resolve_temperature( ...
    base_heat, absorption_gain, ambient_temp_C, peak_deltaT_ref, ...
    thermal_diffusivity, thermal_blur_scale, exposure_time, dx);

if self_enhancing
    transition_temp_C = get_param(params, 'transition_temp_C', 35.0);
    transition_width_C = get_param(params, 'transition_width_C', 2.0);
    gain_low = get_param(params, 'absorption_gain_low', 1.0);
    gain_high = get_param(params, 'absorption_gain_high', 2.5);
    iterations = max(1, round(get_param(params, 'absorption_iterations', 4)));

    for idx = 1:iterations
        phase_fraction = 1 ./ (1 + exp(-(temperature_C - transition_temp_C) ...
            ./ max(transition_width_C, eps)));
        absorption_gain = gain_low + (gain_high - gain_low) .* phase_fraction;
        temperature_C = resolve_temperature( ...
            base_heat, absorption_gain, ambient_temp_C, peak_deltaT_ref, ...
            thermal_diffusivity, thermal_blur_scale, exposure_time, dx);
    end
else
    phase_fraction = zeros(size(base_heat));
end

gel_time_s = compute_arrhenius_gel_time(temperature_C, params);
gel_dose = exposure_time ./ max(gel_time_s, eps);
gel_dose(~isfinite(gel_dose)) = 0;

components = struct();
components.base_heat = base_heat;
components.absorption_gain = absorption_gain;
components.phase_fraction = phase_fraction;
components.gel_time_s = gel_time_s;
components.temperature_C = temperature_C;
components.cavitation_dose = zeros(size(gel_dose));
components.thermal_dose = gel_dose;
components.thermal_contribution = gel_dose;
components.penalty = zeros(size(gel_dose));
components.penalty_contribution = zeros(size(gel_dose));
components.quality_risk = zeros(size(gel_dose));
components.cure_mechanism = get_param(params, 'cure_mechanism', 'arrhenius_thermal');
components.threshold = get_param(params, 'threshold', 1.0);
end

function temperature_C = resolve_temperature(base_heat, absorption_gain, ...
    ambient_temp_C, peak_deltaT_ref, thermal_diffusivity, thermal_blur_scale, ...
    exposure_time, dx)
heat_source = base_heat .* absorption_gain;
diffusion_sigma_px = thermal_blur_scale ...
    * sqrt(4 * thermal_diffusivity * max(exposure_time, eps)) / dx;
temperature_C = ambient_temp_C ...
    + peak_deltaT_ref .* imgaussfilt(heat_source, diffusion_sigma_px);
end

function gel_time_s = compute_arrhenius_gel_time(temperature_C, params)
R = 8.31446261815324;
Ea = get_param(params, 'arrhenius_Ea_J_mol', 80e3);
gel_time_ref_s = get_param(params, 'gel_time_ref_s', 2.0);
gel_time_ref_temp_C = get_param(params, 'gel_time_ref_temp_C', 80.0);

T = max(double(temperature_C) + 273.15, 1);
T_ref = gel_time_ref_temp_C + 273.15;
gel_time_s = gel_time_ref_s .* exp((Ea ./ R) .* (1 ./ T - 1 ./ T_ref));
end

function value = get_param(params, field_name, default_value)
if isfield(params, field_name)
    value = params.(field_name);
else
    value = default_value;
end
end
