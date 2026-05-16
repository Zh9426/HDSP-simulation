# Mainline Cure Systems

这里单列主仿真流程中的两套固化体系完整脚本包。

## 文件夹

### `01_pre_cavitation_arrhenius_mainline__c496905`

- 对应体系：声空化模型开始前的稳定热固化 / Arrhenius 主流程
- 历史锚点：`c496905`
- 提交时间：`2026-04-25 11:23:18 +0800`
- 主要入口：
  - `src/HDSPdebug.m`
- 同包保留：
  - `src/PANN_Holography.py`
  - `src/compute_asm_focus_field.m`
  - `src/error_diffuse_quantize_layers.m`
  - `src/project_phase_to_board.m`
  - `src/export_exit_amp_surrogate_run.m`
  - `src/train_exit_amp_surrogate.py`
  - `src/codex_analysis/`
  - `src/tools/`
- 说明：
  - 这是我回溯后确认的“空化融合固化开始前”更合理的稳定主脚本版本
  - 它仍保留 `target_for_python.mat -> dl_phase_init.mat` 的 MATLAB/Python 中转契约
  - 它使用 `Arrhenius_Omega` 热剂量闭环，但还没有 `Omega_cavitation`、`cavitation_activation_2d`、`threshold_cavitation_plus_arrhenius` 这些空化融合字段

### `01_arrhenius_thermal_mainline`

- 状态：已过时，不再作为“空化前稳定热主流程”的推荐版本
- 原因：
  - 该目录对应的 `2a953a3b` 时间过早，物理参数和主流程结构都偏老
  - 现在应优先使用上面的 `01_pre_cavitation_arrhenius_mainline__c496905`

### `02_pdms_cavitation_mainline`

- 对应体系：PDMS 空化剂量主导固化主流程
- 历史锚点：`35df2a62`
- 主要入口：
  - `src/HDSPdebug.m`
- 同包保留：
  - `src/PANN_Holography.py`
  - `src/compute_cavitation_activity_map.m`
  - `src/compute_cavitation_cure_score.m`
  - `src/compute_cavitation_dose_rate.m`
  - `src/compute_cure_feedback_terms.m`
  - `src/compute_thermal_aux_increment.m`
  - `src/select_cure_threshold.m`
  - 以及主流程相位板/出口场依赖
- 说明：
  - 这是主流程中改为空化剂量主导后的一整套 PDMS 固化体系
  - 同样保留 `target_for_python.mat -> dl_phase_init.mat` 的 MATLAB/Python 中转契约

## 当前定位

这两个文件夹的用途是“把主仿真流程中的两套固化体系单独拎出来”。

它们现在已经可以作为独立审查入口使用，但还没有完成逐文件兼容性复跑验证。

## 版本边界说明

- `2026-04-25 11:23:18 +0800` 的 `c496905`：
  - 目前作为“开始做声空化模型前”的稳定热主流程版本
- `2026-04-27 21:31:03 +0800` 的 `01c1a11`：
  - 虽然时间更晚，但 `HDSPdebug.m` 已经包含 `Omega_cavitation` 等空化融合字段
  - 不再归入“空化前热主流程”
- `2026-04-27 22:20:07 +0800` 的 `3f84a40`：
  - 明确进入 trigger-led cavitation 模型阶段
