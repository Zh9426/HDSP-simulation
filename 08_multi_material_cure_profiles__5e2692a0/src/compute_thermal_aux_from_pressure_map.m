function thermal_dose = compute_thermal_aux_from_pressure_map(p_amp, exposure_time, params, dx)
arguments
    p_amp
    exposure_time (1, 1) double {mustBeNonnegative}
    params struct
    dx (1, 1) double {mustBePositive}
end

p_amp = double(p_amp);
target_pressure_ref = get_param(params, 'thermal_pressure_ref', 2.25e6);
thermal_peak_deltaT = get_param(params, 'thermal_peak_deltaT', 8.0);
thermal_delta_ref = get_param(params, 'thermal_delta_ref', 20.0);
thermal_dose_time = get_param(params, 'thermal_dose_time', 0.12);
thermal_diffusivity = get_param(params, 'thermal_diffusivity', 1.0e-7);
thermal_blur_scale = get_param(params, 'thermal_blur_scale', 1.0);

heat_source = (p_amp ./ max(target_pressure_ref, eps)).^2;
if max(heat_source(:)) > 0
    heat_source = heat_source ./ max(heat_source(:));
end

diffusion_sigma_px = thermal_blur_scale ...
    * sqrt(4 * thermal_diffusivity * max(exposure_time, eps)) / dx;
bulk_temp_rise = thermal_peak_deltaT .* imgaussfilt(heat_source, diffusion_sigma_px);
thermal_dose = bulk_temp_rise ./ thermal_delta_ref ...
    .* (exposure_time ./ max(thermal_dose_time, eps));
end

function value = get_param(params, field_name, default_value)
if isfield(params, field_name)
    value = params.(field_name);
else
    value = default_value;
end
end
