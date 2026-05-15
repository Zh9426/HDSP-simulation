function stage = hdsp_disabled_stage(name)
stage = struct();
stage.name = char(name);
stage.enabled = false;
stage.status = "disabled";
stage.mask = [];
stage.score = NaN;
stage.metrics = struct();
end

