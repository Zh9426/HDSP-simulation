function tests = test_compute_cure_feedback_terms
tests = functiontests(localfunctions);
end

function testThermalFeedbackDependsOnlyOnCureFraction(testCase)
params = baseParams();
chi_focal = single([0.0, 0.5; 1.0, 0.25]);
cavitation_trigger = single([0.1, 0.8; 0.4, 1.0]);
cavitation_growth = single([0.3, 0.9; 0.7, 0.2]);

[conductivity_multiplier, absorption_multiplier, reaction_multiplier] = ...
    compute_cure_feedback_terms(params, chi_focal, cavitation_trigger, cavitation_growth);

verifyEqual(testCase, conductivity_multiplier, single([1.0, 1.1; 1.2, 1.05]), 'AbsTol', 1e-6);
verifyEqual(testCase, absorption_multiplier, single([1.0, 1.25; 1.5, 1.125]), 'AbsTol', 1e-6);
verifyEqual(testCase, reaction_multiplier, single([1.4, 4.2; 2.6, 5.0]), 'AbsTol', 1e-6);
end

function testGrowthNoLongerInflatesReactionMultiplier(testCase)
params = baseParams();
chi_focal = single(zeros(2, 2));
cavitation_trigger = single([0.0, 0.5; 1.0, 0.25]);
cavitation_growth = single(ones(2, 2));

[~, ~, reaction_multiplier] = ...
    compute_cure_feedback_terms(params, chi_focal, cavitation_trigger, cavitation_growth);

verifyEqual(testCase, reaction_multiplier, single([1.0, 3.0; 5.0, 2.0]), 'AbsTol', 1e-6);
end

function params = baseParams()
params = struct( ...
    'conductivity_gain', 0.2, ...
    'absorption_gain', 0.5, ...
    'trigger_gain', 4.0, ...
    'growth_gain', 0.0);
end
