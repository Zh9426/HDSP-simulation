function out = hdsp_normalize01(x)
x = double(x);
mx = max(x(:));
if mx <= 0 || ~isfinite(mx)
    out = zeros(size(x));
else
    out = x ./ mx;
end
end

