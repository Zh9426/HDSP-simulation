import torch
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pann_quality_metrics import aggregate_z_quality_terms, compute_cure_quality_terms


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
    assert uniform_terms["target_peak_over_mean"] < partial_terms["target_peak_over_mean"]
    assert uniform_terms["peak_balance_loss"] < partial_terms["peak_balance_loss"]


def test_cure_quality_penalizes_target_internal_spikes():
    target, halo, far_dark = make_masks()
    balanced = torch.zeros((8, 8), dtype=torch.float32)
    balanced[target > 0.5] = 0.72

    spiky = torch.zeros((8, 8), dtype=torch.float32)
    spiky[target > 0.5] = 0.55
    spiky[2:3, 2:6] = 1.0

    balanced_terms = compute_cure_quality_terms(balanced, target, halo, far_dark)
    spiky_terms = compute_cure_quality_terms(spiky, target, halo, far_dark)

    assert balanced_terms["target_p95_over_mean"] < spiky_terms["target_p95_over_mean"]
    assert balanced_terms["target_peak_over_mean"] < spiky_terms["target_peak_over_mean"]
    assert balanced_terms["peak_balance_loss"] < spiky_terms["peak_balance_loss"]


def test_cure_quality_prefers_narrow_target_pressure_band():
    target, halo, far_dark = make_masks()
    narrow = torch.zeros((8, 8), dtype=torch.float32)
    narrow[target > 0.5] = 0.72

    wide = torch.zeros((8, 8), dtype=torch.float32)
    wide[target > 0.5] = 0.72
    wide[2:3, 2:6] = 0.95
    wide[5:6, 2:6] = 0.45

    narrow_terms = compute_cure_quality_terms(narrow, target, halo, far_dark)
    wide_terms = compute_cure_quality_terms(wide, target, halo, far_dark)

    assert narrow_terms["target_p05_over_p50"] > wide_terms["target_p05_over_p50"]
    assert narrow_terms["target_p95_over_p50"] < wide_terms["target_p95_over_p50"]
    assert narrow_terms["target_band_loss"] < wide_terms["target_band_loss"]


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


def test_dump_zone_is_excluded_from_non_dump_dark_penalty():
    target, halo, far_dark = make_masks()
    amp = torch.zeros((8, 8), dtype=torch.float32)
    amp[target > 0.5] = 0.7
    amp[0:2, :] = 0.8

    dump = torch.zeros_like(target)
    dump[0:2, :] = 1.0

    no_dump_terms = compute_cure_quality_terms(amp, target, halo, far_dark)
    dump_terms = compute_cure_quality_terms(amp, target, halo, far_dark, dump_mask=dump)

    assert dump_terms["dump_energy_fraction"] > 0
    assert dump_terms["dark_area_fraction"] < no_dump_terms["dark_area_fraction"]
    assert dump_terms["non_dump_dark_energy_fraction"] < no_dump_terms["non_dump_dark_energy_fraction"]


def test_cure_quality_prefers_absolute_target_strength_when_shape_matches():
    target, halo, far_dark = make_masks()
    amp_norm = torch.zeros((8, 8), dtype=torch.float32)
    amp_norm[target > 0.5] = 0.72

    weak_raw = amp_norm * 0.2
    strong_raw = amp_norm * 1.0

    weak_terms = compute_cure_quality_terms(
        amp_norm,
        target,
        halo,
        far_dark,
        pred_amp_raw=weak_raw,
        target_mean_amp_goal=0.55,
    )
    strong_terms = compute_cure_quality_terms(
        amp_norm,
        target,
        halo,
        far_dark,
        pred_amp_raw=strong_raw,
        target_mean_amp_goal=0.55,
    )

    assert strong_terms["target_mean_amp_loss"] < weak_terms["target_mean_amp_loss"]
    assert strong_terms["quality_score"] > weak_terms["quality_score"]


def test_z_quality_aggregation_penalizes_the_worst_plane():
    target, halo, far_dark = make_masks()
    good = torch.zeros((8, 8), dtype=torch.float32)
    good[target > 0.5] = 0.75

    weak = torch.zeros((8, 8), dtype=torch.float32)
    weak[target > 0.5] = 0.55

    good_terms = compute_cure_quality_terms(good, target, halo, far_dark)
    weak_terms = compute_cure_quality_terms(weak, target, halo, far_dark)
    aggregate = aggregate_z_quality_terms([good_terms, weak_terms])

    assert aggregate["mean_target_coverage"] > aggregate["worst_target_coverage"]
    assert aggregate["worst_target_coverage_loss"] > 0
    assert aggregate["worst_low_quantile_loss"] >= 0


if __name__ == "__main__":
    test_cure_quality_prefers_uniform_target_over_hot_partial_target()
    test_cure_quality_penalizes_target_internal_spikes()
    test_cure_quality_prefers_narrow_target_pressure_band()
    test_dark_area_loss_ignores_single_hotspot_more_than_area_leakage()
    test_dump_zone_is_excluded_from_non_dump_dark_penalty()
    test_cure_quality_prefers_absolute_target_strength_when_shape_matches()
    test_z_quality_aggregation_penalizes_the_worst_plane()
