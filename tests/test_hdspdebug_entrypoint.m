function tests = test_hdspdebug_entrypoint
tests = functiontests(localfunctions);
end

function testHdspdebugExposesProfileReports(testCase)
run('HDSPdebug.m');

verifyTrue(testCase, exist('cure_report', 'var') == 1);
verifyTrue(testCase, isfield(cure_report, 'system_report'));
verifyEqual(testCase, numel(cure_report.system_report.records), 3);
end
