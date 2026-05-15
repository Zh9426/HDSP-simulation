function result = select_cure_threshold(cure_score, target_mask, threshold_candidates, params)
arguments
    cure_score
    target_mask
    threshold_candidates
    params = struct()
end

cure_score = double(cure_score);
target_mask = logical(target_mask);
threshold_candidates = double(threshold_candidates(:));
roi_pixels = sum(target_mask(:));

metrics = struct( ...
    'threshold', num2cell(threshold_candidates), ...
    'IoU', num2cell(zeros(size(threshold_candidates))), ...
    'Dice', num2cell(zeros(size(threshold_candidates))), ...
    'over_cure_ratio', num2cell(zeros(size(threshold_candidates))), ...
    'under_cure_ratio', num2cell(zeros(size(threshold_candidates))), ...
    'cured_coverage', num2cell(zeros(size(threshold_candidates))), ...
    'cured_mask', repmat({false(size(target_mask))}, size(threshold_candidates)));

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

    metrics(idx).threshold = threshold;
    metrics(idx).IoU = IoU;
    metrics(idx).Dice = Dice;
    metrics(idx).over_cure_ratio = over_cure_ratio;
    metrics(idx).under_cure_ratio = under_cure_ratio;
    metrics(idx).cured_coverage = cured_coverage;
    metrics(idx).cured_mask = cured_mask;
end

if nargin < 4 || isempty(fieldnames(params))
    result = select_by_iou_lexicographic(metrics);
    return;
end

cfg = build_selection_params(params);
result = select_by_balanced_score(metrics, cfg);
end

function result = select_by_iou_lexicographic(metrics)
best_idx = 1;
for idx = 2:numel(metrics)
    cur = metrics(idx);
    best = metrics(best_idx);
    is_better = cur.IoU > best.IoU + 1e-12 ...
        || (abs(cur.IoU - best.IoU) <= 1e-12 && cur.over_cure_ratio < best.over_cure_ratio - 1e-12) ...
        || (abs(cur.IoU - best.IoU) <= 1e-12 ...
        && abs(cur.over_cure_ratio - best.over_cure_ratio) <= 1e-12 ...
        && cur.under_cure_ratio < best.under_cure_ratio - 1e-12);
    if is_better
        best_idx = idx;
    end
end
result = metrics(best_idx);
end

function cfg = build_selection_params(params)
cfg = struct();
cfg.over_cure_target = get_param_or_default(params, 'over_cure_target', 0.20);
cfg.under_cure_target = get_param_or_default(params, 'under_cure_target', 0.12);
cfg.over_cure_weight = get_param_or_default(params, 'over_cure_weight', 1.20);
cfg.under_cure_weight = get_param_or_default(params, 'under_cure_weight', 1.00);
cfg.dice_weight = get_param_or_default(params, 'dice_weight', 0.15);
cfg.iou_weight = get_param_or_default(params, 'iou_weight', 1.00);
cfg.iou_drop_tolerance = get_param_or_default(params, 'iou_drop_tolerance', inf);
cfg.global_penalty_weight = get_param_or_default(params, 'global_penalty_weight', 0.10);
cfg.selection_mode = get_param_or_default(params, 'selection_mode', 'near_best_iou');
end

function result = select_by_balanced_score(metrics, cfg)
IoU_vec = [metrics.IoU];
Dice_vec = [metrics.Dice];
over_vec = [metrics.over_cure_ratio];
under_vec = [metrics.under_cure_ratio];

max_iou = max(IoU_vec);
feasible = IoU_vec >= (max_iou - cfg.iou_drop_tolerance);
if ~any(feasible)
    feasible = true(size(IoU_vec));
end

over_excess = max(over_vec - cfg.over_cure_target, 0);
under_excess = max(under_vec - cfg.under_cure_target, 0);
penalty = cfg.over_cure_weight .* over_excess ...
    + cfg.under_cure_weight .* under_excess ...
    + cfg.global_penalty_weight .* (over_vec + under_vec);

if strcmpi(cfg.selection_mode, 'near_best_iou')
    penalty(~feasible) = inf;
    [min_penalty, ~] = min(penalty);
    candidate = feasible & abs(penalty - min_penalty) <= 1e-12;
    candidate_score = IoU_vec + 1e-3 .* Dice_vec;
    candidate_score(~candidate) = -inf;
    [~, best_idx] = max(candidate_score);
    result = metrics(best_idx);
    result.selection_score = candidate_score(best_idx);
    result.selection_penalty = penalty(best_idx);
    return;
end

score = cfg.iou_weight .* IoU_vec + cfg.dice_weight .* Dice_vec - penalty;
score(~feasible) = -inf;

[~, best_idx] = max(score);
result = metrics(best_idx);
result.selection_score = score(best_idx);
result.selection_penalty = penalty(best_idx);
end

function value = get_param_or_default(s, field_name, default_value)
if isfield(s, field_name)
    if ischar(default_value) || isstring(default_value)
        value = char(s.(field_name));
    else
        value = double(s.(field_name));
    end
else
    if ischar(default_value) || isstring(default_value)
        value = char(default_value);
    else
        value = double(default_value);
    end
end
end
