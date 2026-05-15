function cure = make_cure_result(name, dose, mask, target_mask)
target_mask = logical(target_mask);
mask = logical(mask);
intersection = mask & target_mask;
union_mask = mask | target_mask;
cure = struct();
cure.name = name;
cure.enabled = true;
cure.status = "ok";
cure.dose = dose;
cure.mask = mask;
cure.score = sum(intersection(:)) / (sum(union_mask(:)) + eps);
cure.metrics = struct();
cure.metrics.iou = cure.score;
cure.metrics.dice = 2 * sum(intersection(:)) / (sum(mask(:)) + sum(target_mask(:)) + eps);
cure.metrics.over_cure_ratio = sum(mask(:) & ~target_mask(:)) / (sum(target_mask(:)) + eps);
cure.metrics.under_cure_ratio = sum(~mask(:) & target_mask(:)) / (sum(target_mask(:)) + eps);
cure.metrics.coverage = sum(intersection(:)) / (sum(target_mask(:)) + eps);
end

