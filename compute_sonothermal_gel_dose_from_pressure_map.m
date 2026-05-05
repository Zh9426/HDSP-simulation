function [gel_dose, temperature_C, components] = compute_sonothermal_gel_dose_from_pressure_map( ...
    p_amp, exposure_time, params, dx)
arguments
    p_amp
    exposure_time (1, 1) double {mustBeNonnegative}
    params struct
    dx (1, 1) double {mustBePositive}
end

p_amp = double(p_amp);
if strcmp(get_param(params, 'sonothermal_reference', ''), 'Kuang2023_Science_DAVP')
    [gel_dose, temperature_C, components] = compute_kuang2023_sonoink_dose( ...
        p_amp, exposure_time, params, dx);
    return;
end

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

function [gel_dose, temperature_C, components] = compute_kuang2023_sonoink_dose( ...
    p_amp, exposure_time, params, dx)
ambient_temp_C = get_param(params, 'ambient_temp_C', 24.0);
pressure_ref = get_param(params, 'thermal_pressure_ref', 45e6);
pressure_exponent = get_param(params, 'sonothermal_pressure_exponent', 2.0);
rate_low_C_s = get_param(params, 'sonothermal_rate_low_C_s', 4.8);
rate_high_C_s = get_param(params, 'sonothermal_rate_high_C_s', 11.3);
transition_temp_C = get_param(params, 'transition_temp_C', 35.0);
transition_width_C = get_param(params, 'transition_width_C', 1.0);
thermal_diffusivity = get_param(params, 'thermal_diffusivity', 1.0e-7);
thermal_blur_scale = get_param(params, 'thermal_blur_scale', 1.0);
dt_target = get_param(params, 'sonothermal_time_step_s', 0.02);
max_temperature_C = get_param(params, 'sonothermal_max_temperature_C', 85.0);
cure_temp_C = get_param(params, 'cure_temp_C', 67.0);
require_cure_temperature = get_param(params, 'require_cure_temperature', true);

dt = min(max(dt_target, 1e-4), max(exposure_time, 1e-4));
n_steps = max(1, ceil(exposure_time / dt));
dt = exposure_time / n_steps;

pressure_drive = (max(p_amp, 0) ./ max(pressure_ref, eps)) .^ pressure_exponent;
temperature_C = ambient_temp_C .* ones(size(p_amp));
gel_dose = zeros(size(p_amp));
phase_fraction = zeros(size(p_amp));
rate_map_C_s = zeros(size(p_amp));

for idx = 1:n_steps
    phase_fraction = 1 ./ (1 + exp(-(temperature_C - transition_temp_C) ...
        ./ max(transition_width_C, eps)));
    rate_map_C_s = (rate_low_C_s + (rate_high_C_s - rate_low_C_s) ...
        .* phase_fraction) .* pressure_drive;
    deltaT = diffuse_increment(rate_map_C_s .* dt, thermal_diffusivity, ...
        thermal_blur_scale, dt, dx);
    temperature_C = min(temperature_C + deltaT, max_temperature_C);

    gel_time_s = compute_arrhenius_gel_time(temperature_C, params);
    increment = dt ./ max(gel_time_s, eps);
    if require_cure_temperature
        increment(temperature_C < cure_temp_C) = 0;
    end
    gel_dose = gel_dose + increment;
end

gel_dose(~isfinite(gel_dose)) = 0;

components = struct();
components.base_heat = pressure_drive;
components.absorption_gain = 1 + phase_fraction;
components.phase_fraction = phase_fraction;
components.heating_rate_C_s = rate_map_C_s;
components.gel_time_s = compute_arrhenius_gel_time(temperature_C, params);
components.temperature_C = temperature_C;
components.cavitation_dose = zeros(size(gel_dose));
components.thermal_dose = gel_dose;
components.thermal_contribution = gel_dose;
components.penalty = zeros(size(gel_dose));
components.penalty_contribution = zeros(size(gel_dose));
components.quality_risk = max(0, temperature_C - max_temperature_C);
components.cure_mechanism = get_param(params, 'cure_mechanism', 'self_enhancing_sonothermal');
components.threshold = get_param(params, 'threshold', 1.0);
components.cure_temp_C = cure_temp_C;
components.reference = get_param(params, 'sonothermal_reference', 'Kuang2023_Science_DAVP');
end

function deltaT = diffuse_increment(deltaT_source, thermal_diffusivity, ...
    thermal_blur_scale, dt, dx)
diffusion_sigma_px = thermal_blur_scale ...
    * sqrt(4 * thermal_diffusivity * max(dt, eps)) / dx;
deltaT = imgaussfilt(deltaT_source, diffusion_sigma_px);
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
