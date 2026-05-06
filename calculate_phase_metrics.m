function metrics = calculate_phase_metrics(phase_map, source_mask, target_amp, focus_amp, label)
%CALCULATE_PHASE_METRICS Metrics describing phase-computation behavior.
phase = wrap_phase(double(phase_map));
active_phase = phase(source_mask);
target_norm = target_amp / (max(target_amp(:)) + eps);
focus_norm = focus_amp / (max(focus_amp(:)) + eps);

metrics.label = label;
metrics.active_pixel_count = nnz(source_mask);
metrics.phase_mean_rad = circ_mean(active_phase);
metrics.phase_resultant_length = abs(mean(exp(1i * active_phase)));
metrics.phase_circular_variance = 1 - metrics.phase_resultant_length;
metrics.phase_std_rad = sqrt(-2 * log(max(metrics.phase_resultant_length, eps)));
metrics.phase_gradient_mean_rad = mean_phase_gradient(phase, source_mask);
metrics.phase_gradient_p90_rad = percentile_phase_gradient(phase, source_mask, 90);
metrics.phase_wrap_fraction = mean(abs(angle(exp(1i * active_phase))) > 0.95 * pi);

pred_centered = focus_norm(:) - mean(focus_norm(:));
target_centered = target_norm(:) - mean(target_norm(:));
metrics.asm_target_pcc = sum(pred_centered .* target_centered) / ...
    (sqrt(sum(pred_centered.^2) * sum(target_centered.^2)) + eps);
metrics.asm_nmse = sum((focus_norm(:) - target_norm(:)).^2) / (sum(target_norm(:).^2) + eps);
end

function value = circ_mean(phase_values)
value = angle(mean(exp(1i * phase_values)));
end

function value = mean_phase_gradient(phase, mask)
[gx, gy] = phase_gradients(phase);
grad_mag = hypot(gx, gy);
value = mean(grad_mag(mask));
end

function value = percentile_phase_gradient(phase, mask, p)
[gx, gy] = phase_gradients(phase);
grad_mag = hypot(gx, gy);
value = prctile(grad_mag(mask), p);
end

function [gx, gy] = phase_gradients(phase)
gx = angle(exp(1i * diff(phase, 1, 1)));
gx = [gx; gx(end, :)];
gy = angle(exp(1i * diff(phase, 1, 2)));
gy = [gy, gy(:, end)];
end
