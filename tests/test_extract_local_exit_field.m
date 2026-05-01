function tests = test_extract_local_exit_field
tests = functiontests(localfunctions);
end

function testExtractsPixelSpecificZSamples(testCase)
volume = complex(zeros(2, 3, 5));
for row = 1:2
    for col = 1:3
        for z_idx = 1:5
            volume(row, col, z_idx) = row + 10 * col + 100 * z_idx + 1i * z_idx;
        end
    end
end
local_z = [1, 3, 5; 2, 4, 1];
mask = [true, true, false; true, false, true];

field = extract_local_exit_field(volume, local_z, mask);

expected = complex(zeros(2, 3));
expected(1, 1) = volume(1, 1, 1);
expected(1, 2) = volume(1, 2, 3);
expected(2, 1) = volume(2, 1, 2);
expected(2, 3) = volume(2, 3, 1);
verifyEqual(testCase, field, expected);
end

function testRejectsOutOfRangeIndices(testCase)
volume = complex(zeros(2, 2, 3));
local_z = [1, 4; 2, 3];
mask = true(2, 2);

verifyError(testCase, @() extract_local_exit_field(volume, local_z, mask), 'extract_local_exit_field:OutOfRange');
end
