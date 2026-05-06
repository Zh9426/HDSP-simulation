# IASA 0211 Basic

Source commit: `4269d1c`

This directory now keeps only the padded IASA initial-phase computation. The historical full script also contained target construction, k-Wave propagation, and plotting; those responsibilities belong to separate modules.

```matlab
target = build_target_A_letter_edge_blur_0302(256, 40e-3);
phase_result = compute_initial_phase_IASA_0211(target.image);
imagesc(phase_result.phase); axis image;
```
