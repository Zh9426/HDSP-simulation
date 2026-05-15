function ctx = cure_cavitation_dose_led_score_0501(ctx)
p = double(ctx.field.focus_amp);
params = ctx.params;
activity = (p - params.cavitation_onset_pa) ./ ...
    (params.cavitation_saturation_pa - params.cavitation_onset_pa + eps);
activity = min(max(activity, 0), 1);
cloud = imgaussfilt(activity, 1.2);
thermal_aux = 0.18 * hdsp_normalize01(p.^2);
dose = cloud + thermal_aux;
threshold = max(0.45, prctile(dose(ctx.target.mask), 35));
mask = dose >= threshold;
ctx.cure = make_cure_result('cavitation_dose_led_score_0501', dose, mask, ctx.target.mask);
ctx.cure.threshold = threshold;
end

