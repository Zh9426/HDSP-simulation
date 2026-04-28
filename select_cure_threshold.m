function result = select_cure_threshold(cure_score, target_mask, threshold_candidates)
arguments
    cure_score
    target_mask
    threshold_candidates
end

cure_score = double(cure_score);
target_mask = logical(target_mask);
threshold_candidates = double(threshold_candidates(:));
roi_pixels = sum(target_mask(:));

best = struct( ...
    'threshold', threshold_candidates(1), ...
    'IoU', -inf, ...
    'Dice', 0, ...
    'over_cure_ratio', inf, ...
    'under_cure_ratio', inf, ...
    'cured_coverage', 0, ...
    'cured_mask', false(size(target_mask)));

for idx = 1:numel(threshold_candidates)
    threshold = threshold_candidates(idx);
    cured_mask = cure_score >= threshold;
    intersection = cured_mask & target_mask;
    union_mask = cured_mask | target_mask;
    IoU = sum(intersection(:)) / (sum(union_mask(:)) + 1e-10);
    Dice = 2 * sum(intersection(:)) / (sum(target_mask(:)) + sum(cured_mask(:)) + 1e-10);
    over_cure_ratio = sum(cured_mask(:) & ~target_mask(:)) / max(roi_pixels, eps);
    under_cure_ratio = sum(~cured_mask(:) & target_mask(:)) / max(roi_pixels, eps);
    cured_coverage = sum(intersection(:)) / max(roi_pixels, eps);

    is_better = IoU > best.IoU + 1e-12 ...
        || (abs(IoU - best.IoU) <= 1e-12 && over_cure_ratio < best.over_cure_ratio - 1e-12) ...
        || (abs(IoU - best.IoU) <= 1e-12 ...
        && abs(over_cure_ratio - best.over_cure_ratio) <= 1e-12 ...
        && under_cure_ratio < best.under_cure_ratio - 1e-12);

    if is_better
        best.threshold = threshold;
        best.IoU = IoU;
        best.Dice = Dice;
        best.over_cure_ratio = over_cure_ratio;
        best.under_cure_ratio = under_cure_ratio;
        best.cured_coverage = cured_coverage;
        best.cured_mask = cured_mask;
    end
end

result = best;
end
