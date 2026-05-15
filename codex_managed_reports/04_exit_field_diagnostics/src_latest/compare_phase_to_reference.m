function result = compare_phase_to_reference(measured_complex, reference_phase, mask, amp_threshold_ratio)
arguments
    measured_complex
    reference_phase
    mask
    amp_threshold_ratio (1, 1) double = 0.05
end

mask = logical(mask);
amp = abs(measured_complex);
masked_amp = amp(mask);
if isempty(masked_amp)
    valid_mask = false(size(mask));
else
    valid_mask = mask & amp >= amp_threshold_ratio * max(masked_amp(:));
end

measured_phase = angle(measured_complex);
same_delta = angle(exp(1i .* (measured_phase(valid_mask) - reference_phase(valid_mask))));
opposite_delta = angle(exp(1i .* (measured_phase(valid_mask) + reference_phase(valid_mask))));

same_stats = phase_delta_stats(same_delta);
opposite_stats = phase_delta_stats(opposite_delta);

if same_stats.rms_rad <= opposite_stats.rms_rad
    best_sign = "same";
else
    best_sign = "opposite";
end

result = struct();
result.same_sign = same_stats;
result.opposite_sign = opposite_stats;
result.best_sign = best_sign;
result.valid_mask = valid_mask;
result.valid_pixels = nnz(valid_mask);
result.total_mask_pixels = nnz(mask);
result.valid_fraction = nnz(valid_mask) / max(nnz(mask), 1);
result.amp_threshold_ratio = amp_threshold_ratio;
end

function stats = phase_delta_stats(delta)
if isempty(delta)
    stats = struct('coherence', NaN, 'global_offset_rad', NaN, 'rms_rad', NaN, 'mean_abs_rad', NaN);
    return;
end

phasor_mean = mean(exp(1i .* delta(:)));
global_offset = angle(phasor_mean);
centered_delta = angle(exp(1i .* (delta(:) - global_offset)));

stats = struct();
stats.coherence = abs(phasor_mean);
stats.global_offset_rad = global_offset;
stats.rms_rad = sqrt(mean(centered_delta .^ 2));
stats.mean_abs_rad = mean(abs(centered_delta));
end
