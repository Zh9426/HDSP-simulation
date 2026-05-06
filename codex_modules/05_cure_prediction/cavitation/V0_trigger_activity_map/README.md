# V0 Trigger Activity Map

This module keeps only the trigger-led cavitation activity-map calculation from
the historical workflow.

## Function

- `compute_cavitation_activity_map(p_amp, params)`

## Inputs

- `p_amp`: pressure-amplitude field.
- `params`: struct with pressure thresholds and optional mask/smoothing fields.

## Output

The function returns a struct with activation, saturation, penalty, trigger,
growth, and activity maps.

The original mixed full-flow driver was removed from this module directory so
the folder can be used as a callable cure-prediction component.
