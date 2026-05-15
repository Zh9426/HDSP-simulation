# HDSP 历史节点重跑清单

本清单用于固定 8 个核心重跑节点的代码来源、主入口、建议复制文件和建议导出物。

## 1. `cc3dced2` 相位反演起点

- 目录：`01_hologram_phase_recovery__IASA_0221_cc3dced2`
- 主题：IASA 0221 版本，相位反演早期基线
- 历史提交：`cc3dced24c06b0ad394da86e7ed49562126ed7da`
- 主入口：`HDSP_debug0209.m`
- 建议复制到 `src/`：
  - `HDSP_debug0209.m`
- 建议导出图表：
  - 目标图案与重建振幅对比
  - 全息相位图
  - 最佳焦面或出口相位诊断图
- 建议导出 summary：
  - IASA 迭代轮次
  - 重建误差或 MSE
  - 最佳焦面位置
  - 早期聚焦/对比度指标
- 重跑理由：
  - 它是任务书中“迭代相位恢复算法”的最早可复核起点
  - 后续所有相位优化结果都需要一个原始基线

## 2. `a4a3cd8e` 相位板结构映射

- 目录：`02_phase_board_mapping__thickness_built_a4a3cd8e`
- 主题：`thickness_built` 相位板厚度构建
- 历史提交：`a4a3cd8e69cb2bc139baf2601c5f2722f7b74f4c`
- 主入口：`thickness_built.m`
- 建议复制到 `src/`：
  - `thickness_built.m`
- 建议导出图表：
  - wrapped 相位图
  - 实际构建相位图
  - 厚度分布图
  - 相位残差图
- 建议导出 summary：
  - 平均相位量化误差
  - 最大相位量化误差
  - 厚度范围
  - 若能稳定得到，则补充实体透镜出口相位误差
- 重跑理由：
  - 对应任务书“相位板微观结构参数映射”
  - 是从理想相位走向可制造结构的关键节点

## 3. `dc6d9f95` 早期热固化闭环

- 目录：`03_thermal_closure__temp_curing_dc6d9f95`
- 主题：引入温度固化的早期闭环
- 历史提交：`dc6d9f95a8f88942347e9fd94ba5359ac6e03217`
- 主入口：`tempdebug.m`
- 建议复制到 `src/`：
  - `tempdebug.m`
  - 视情况补 `HDSPdebug.m` 仅作对照，不作为首选入口
- 建议导出图表：
  - 目标图案与最佳焦面声压图
  - Z-scan 曲线
  - 温度场图
  - 基于阈值的固化/空化覆盖图
- 建议导出 summary：
  - 最佳焦面位置
  - Correlation
  - NMSE
  - PSNR
  - 峰值声压
  - 固化覆盖率
  - 极值温度
- 重跑理由：
  - 这是最早把声场结果和材料驱动效果接起来的闭环节点
  - 可直接对应任务书中的“仿真结果分析与性能评估”

## 4. `2a953a3b` Arrhenius 热剂量节点

- 目录：`04_arrhenius_thermal_dose__2a953a3b`
- 主题：Arrhenius 动力学引擎与动态声热耦合
- 历史提交：`2a953a3b2c7af09f6e28fc91c63f1519cc7f7fa4`
- 主入口：`tempdebug.m`
- 建议复制到 `src/`：
  - `tempdebug.m`
  - `HDSPdebug.m`
  - `IASAdebug.m`
  - `PANN_Holography.py`
- 建议导出图表：
  - 最佳焦面声压图
  - Z-scan 曲线
  - 温度场图
  - 热剂量或反应度分布图
  - 固化形貌图
- 建议导出 summary：
  - 最佳焦面位置
  - Correlation
  - NMSE
  - PSNR
  - 峰值温度
  - IoU 或对应固化形貌指标
- 重跑理由：
  - 这是“温度阈值后处理”升级为“动力学固化评估”的关键节点
  - 对任务书里的多物理场建模最有代表性

## 5. `79d204af` Python/PANN 相位优化转折

- 目录：`05_python_pann_phase_optimization__79d204af`
- 主题：PANN 主导 IASA
- 历史提交：`79d204afb3ab19a5ae773a8f2d67e0f8aafef965`
- 主入口：`HDSPdebug.m`
- 建议复制到 `src/`：
  - `HDSPdebug.m`
  - `tempdebug.m`
- 说明：
  - 若按原历史流程重跑，需要人为补入 `target_for_python.mat` / `dl_phase_init.mat` 中转
  - 后续可在该目录下补一个本地包装说明，固定 MATLAB -> Python -> MATLAB 的手动流程
- 建议导出图表：
  - Python 初相引导前后对比图
  - 最佳焦面声压图
  - Z-scan 曲线
  - 热固化形貌图
- 建议导出 summary：
  - 最佳焦面位置
  - Correlation
  - 热场极值温度
  - 热交联覆盖率
  - IoU
- 重跑理由：
  - 这是相位求解方法从传统 IASA 向 Python/PANN 引导优化的关键转折
  - 对任务书中的“设计与优化”部分很重要

## 6. `7ef8144b` 出口复场诊断

- 目录：`06_exit_field_diagnostics__7ef8144b`
- 主题：出口平面复场分析
- 历史提交：`7ef8144be47c2604157143d5ca97d9af611c21fc`
- 主入口：`HDSPdebug.m`
- 建议复制到 `src/`：
  - `HDSPdebug.m`
  - `PANN_Holography.py`
  - `compute_asm_focus_field.m`
  - `error_diffuse_quantize_layers.m`
  - `project_phase_to_board.m`
- 可忽略：
  - `2.fig`
  - `__pycache__/...`
  - 资料 PDF / Word
- 建议导出图表：
  - 出口平面振幅图
  - 出口平面相位图
  - 出口复场 ASM 传播结果
  - k-Wave 焦面图
  - Z-scan 曲线
  - 固化形貌图
- 建议导出 summary：
  - Python ASM PCC / SSIM / NMSE
  - IASA ASM PCC / SSIM / NMSE
  - ASM 与 k-Wave 一致性指标
  - 出口面振幅 CV
  - 出口面 min/max ratio
  - Exit-field ASM target PCC
  - Exit-field ASM vs k-Wave PCC
  - IoU / Dice / over-cure / under-cure / coverage
- 重跑理由：
  - 它解释了“理想相位”和“真实厚板输出”之间的失配来源
  - 可直接支撑任务书中的传播规律分析和关键因素识别

## 7. `35df2a62` 空化剂量主导固化

- 目录：`07_cavitation_dose_curing__35df2a62`
- 主题：空化云一致性剂量
- 历史提交：`35df2a62c7f26e3b78232c6ed4dcc02ca5565f96`
- 主入口：`HDSPdebug.m`
- 建议复制到 `src/`：
  - `HDSPdebug.m`
  - `PANN_Holography.py`
  - `build_exit_plane_analysis_defaults.m`
  - `compute_asm_focus_field.m`
  - `compute_cavitation_activity_map.m`
  - `compute_cavitation_cure_score.m`
  - `compute_cavitation_dose_rate.m`
  - `compute_cure_feedback_terms.m`
  - `compute_thermal_aux_increment.m`
  - `error_diffuse_quantize_layers.m`
  - `project_phase_to_board.m`
  - `select_cure_threshold.m`
- 测试参考：
  - `tests/test_compute_cavitation_dose_rate.m`
  - `tests/test_compute_thermal_aux_increment.m`
- 建议导出图表：
  - 出口场与焦面图
  - 空化活性图
  - 空化剂量图
  - 热辅助图
  - 过驱动惩罚图
  - 预测固化图
  - 参数扫描 Top-N 可视化
- 建议导出 summary：
  - 最优 `P / Exp / Cool / Thr`
  - IoU
  - Dice
  - 有效固化 coverage
  - 过固化 / 欠固化
  - 空化剂量 peak / ROI mean
  - 热辅助 ROI mean
  - 过驱动惩罚 ROI mean
  - Top-10 scan records
- 重跑理由：
  - 这是 PDMS 类材料固化机理由热主导转向空化主导的决定性节点
  - 对论文和答辩都属于高价值里程碑

## 8. `5e2692a0` 三材料并列固化系统

- 目录：`08_multi_material_cure_profiles__5e2692a0`
- 主题：材料配套的三套固化系统
- 历史提交：`5e2692a040916cdab672ad984abb889f27415435`
- 主入口：
  - `run_cure_system_profile_suite.m`
  - `simulate_cure_from_pressure_map.m`
- 建议复制到 `src/`：
  - `build_cure_system_profile.m`
  - `compute_sonothermal_gel_dose_from_pressure_map.m`
  - `simulate_cure_from_pressure_map.m`
  - `run_cure_system_profile_suite.m`
  - `default_cure_model_params.m`
  - `compute_cavitation_activity_map.m`
  - `compute_cavitation_cure_score.m`
  - `compute_cavitation_dose_rate.m`
  - `compute_thermal_aux_from_pressure_map.m`
  - `compute_thermal_aux_increment.m`
  - `evaluate_cure_prediction.m`
  - `evaluate_cure_validation_cases.m`
  - `select_cure_visualization_cases.m`
  - `build_hdsp_validation_target.m`
  - `build_pressure_validation_cases.m`
- 测试参考：
  - `tests/test_build_cure_system_profile.m`
  - `tests/test_run_cure_system_profile_suite.m`
  - `tests/test_simulate_cure_system_profiles.m`
- 建议导出图表：
  - 三 profile 的 cured mask 对比图
  - 三 profile 的 score / 温升 / 风险图对比
  - 同一 pressure case 下的对比总览图
- 建议导出 summary：
  - system / mechanism / material
  - IoU
  - Dice
  - coverage
  - over-cure / under-cure
  - score ROI
  - Tmax
  - quality risk peak
- 重跑理由：
  - 这是当前项目架构最完整、最适合任务书收束表达的节点
  - 它把不同材料的固化机理正式并列化，便于形成论文主线

## 下一步执行顺序

1. 先按本清单从历史提交复制源码到各节点 `src/`
2. 每个节点补最小运行说明
3. 统一设计结果导出格式
4. 逐节点重跑并写入 `results_export/`
5. 最后汇总跨节点对比 summary
