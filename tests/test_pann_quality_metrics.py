import torch
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pann_quality_metrics import compute_cure_quality_terms


def make_masks():
    target = torch.zeros((8, 8), dtype=torch.float32)
    target[2:6, 2:6] = 1.0
    halo = torch.zeros_like(target)
    halo[1:7, 1:7] = 1.0
    halo = torch.clamp(halo - target, min=0.0)
    far_dark = 1.0 - torch.clamp(target + halo, max=1.0)
    return target, halo, far_dark


def test_cure_quality_prefers_uniform_target_over_hot_partial_target():
    target, halo, far_dark = make_masks()
    uniform = torch.zeros((8, 8), dtype=torch.float32)
    uniform[target > 0.5] = 0.72

    partial = torch.zeros((8, 8), dtype=torch.float32)
    partial[2:4, 2:6] = 1.0
    partial[4:6, 2:6] = 0.25

    uniform_terms = compute_cure_quality_terms(uniform, target, halo, far_dark)
    partial_terms = compute_cure_quality_terms(partial, target, halo, far_dark)

    assert uniform_terms["quality_score"] > partial_terms["quality_score"]
    assert uniform_terms["target_coverage"] > partial_terms["target_coverage"]
    assert uniform_terms["target_p10_over_p50"] > partial_terms["target_p10_over_p50"]


def test_dark_area_loss_ignores_single_hotspot_more_than_area_leakage():
    target, halo, far_dark = make_masks()
    single_hotspot = torch.zeros((8, 8), dtype=torch.float32)
    single_hotspot[target > 0.5] = 0.7
    single_hotspot[0, 0] = 1.0

    area_leakage = torch.zeros((8, 8), dtype=torch.float32)
    area_leakage[target > 0.5] = 0.7
    area_leakage[0:2, :] = 0.8

    single_terms = compute_cure_quality_terms(single_hotspot, target, halo, far_dark)
    area_terms = compute_cure_quality_terms(area_leakage, target, halo, far_dark)

    assert single_terms["dark_area_fraction"] < area_terms["dark_area_fraction"]
    assert single_terms["dark_area_loss"] < area_terms["dark_area_loss"]
