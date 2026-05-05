function tests = test_select_cure_visualization_cases
tests = functiontests(localfunctions);
end

function testSelectsNamedCasesInStableOrder(testCase)
records = [ ...
    record('target_edge_rolloff', 0.5), ...
    record('ideal_binary', 1.0), ...
    record('blurred_edge', 0.8), ...
    record('speckle_nonuniform', 0.9)];

indices = select_cure_visualization_cases(records, ...
    ["ideal_binary", "blurred_edge", "speckle_nonuniform"]);

verifyEqual(testCase, indices, [2, 3, 4]);
end

function testFallsBackToMostDegradedCase(testCase)
records = [record('case_a', 0.7), record('case_b', 0.4)];

indices = select_cure_visualization_cases(records, "missing_case");

verifyEqual(testCase, indices, 2);
end

function out = record(name, IoU)
out = struct('name', name, 'IoU', IoU);
end
