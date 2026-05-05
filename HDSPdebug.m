close all; clc;

% Lightweight entry point for standalone cure-model validation.
% The detailed PDMS cavitation sanity check and the three material-profile
% comparison are both routed through run_cure_model_sanity_suite().
cure_report = run_cure_model_sanity_suite();
