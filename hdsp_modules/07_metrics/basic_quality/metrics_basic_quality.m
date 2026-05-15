function ctx = metrics_basic_quality(ctx)
target = hdsp_normalize01(ctx.target.amp);
focus = hdsp_normalize01(ctx.field.focus_amp);
mask = ctx.target.mask;
dark = ~mask;
metrics = struct();
metrics.profile_key = ctx.profile.key;
metrics.target_name = ctx.target.name;
metrics.phase_name = ctx.phase.name;
metrics.board_name = ctx.board.name;
metrics.simulation_name = ctx.field.name;
metrics.simulation_status = ctx.field.status;
metrics.nmse = sum((target(:) - focus(:)).^2) / (sum(target(:).^2) + eps);
metrics.pcc = corr_safe(target, focus);
metrics.mean_target_pressure_pa = mean(ctx.field.focus_amp(mask));
metrics.mean_dark_pressure_pa = mean(ctx.field.focus_amp(dark));
metrics.focus_contrast = metrics.mean_target_pressure_pa / (metrics.mean_dark_pressure_pa + eps);
metrics.energy_efficiency = sum(ctx.field.focus_amp(mask).^2) / (sum(ctx.field.focus_amp(:).^2) + eps);
metrics.target_uniformity_cv = std(ctx.field.focus_amp(mask)) / (metrics.mean_target_pressure_pa + eps);
metrics.phase_residual_mean_abs = mean(abs(ctx.board.residual(ctx.phase.source_mask)));
metrics.cure_enabled = isfield(ctx.cure, 'enabled') && ctx.cure.enabled;
if metrics.cure_enabled
    metrics.cure_iou = ctx.cure.metrics.iou;
    metrics.cure_dice = ctx.cure.metrics.dice;
    metrics.over_cure_ratio = ctx.cure.metrics.over_cure_ratio;
    metrics.under_cure_ratio = ctx.cure.metrics.under_cure_ratio;
else
    metrics.cure_iou = NaN;
    metrics.cure_dice = NaN;
    metrics.over_cure_ratio = NaN;
    metrics.under_cure_ratio = NaN;
end
ctx.metrics = metrics;
end

function r = corr_safe(a, b)
a = double(a(:));
b = double(b(:));
a = a - mean(a);
b = b - mean(b);
r = sum(a .* b) / (sqrt(sum(a.^2) * sum(b.^2)) + eps);
end

