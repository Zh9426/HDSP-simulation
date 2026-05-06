# A Letter Edge Blur 0302

Source commit: `1225f33`

This module keeps only the A-letter target construction from the historical 0302-era script. The original full script mixed target definition, IASA, phase-board mapping, k-Wave simulation, and thermal/cure logic; this directory now exposes the target as a reusable function:

```matlab
target = build_target_A_letter_edge_blur_0302(384, 40e-3);
imagesc(target.image); axis image;
```
