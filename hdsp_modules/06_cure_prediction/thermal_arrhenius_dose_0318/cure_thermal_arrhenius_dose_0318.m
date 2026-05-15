function ctx = cure_thermal_arrhenius_dose_0318(ctx)
p = double(ctx.field.focus_amp);
params = ctx.params;
pressure_norm = p / (params.target_pressure_pa + eps);
temperature_rise = 45 * pressure_norm.^2;
temperature_c = 25 + temperature_rise;
rate = exp(0.11 * (temperature_c - 65));
dose = rate * params.exposure_time_s / 0.24;
mask = dose >= params.arrhenius_threshold;
ctx.cure = make_cure_result('thermal_arrhenius_dose_0318', dose, mask, ctx.target.mask);
end

