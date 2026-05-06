function result = evaluate_cure_prediction(cure_score, target_mask, threshold)
arguments
    cure_score
    target_mask
    threshold (1, 1) double
end

cure_score = double(cure_score);
target_mask = logical(target_mask);
cured_mask = cure_score >= threshold;
roi_pixels = sum(target_mask(:));
intersection = cured_mask & target_mask;
union_mask = cured_mask | target_mask;

result = struct();
result.threshold = threshold;
result.IoU = sum(intersection(:)) / (sum(union_mask(:)) + 1e-10);
result.Dice = 2 * sum(intersection(:)) / ...
    (sum(target_mask(:)) + sum(cured_mask(:)) + 1e-10);
result.over_cure_ratio = sum(cured_mask(:) & ~target_mask(:)) / max(roi_pixels, eps);
result.under_cure_ratio = sum(~cured_mask(:) & target_mask(:)) / max(roi_pixels, eps);
result.cured_coverage = sum(intersection(:)) / max(roi_pixels, eps);
result.cured_mask = cured_mask;
end
