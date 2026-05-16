# HDSP 历史节点重跑清单

本清单不再把“历史节点提交”视为“可直接运行的自包含快照”。

从本版开始，每个节点拆成两层：

- `milestone_commit`
  - 用于论文、答辩和项目演化叙事的历史锚点
- `runtime_bundle`
  - 用于实际重跑的兼容运行组合
  - 可以是单提交、同阶段多文件组合，或带手动 MATLAB -> Python 中转的运行集合

另见 [runtime_compatibility_audit.md](./runtime_compatibility_audit.md)。

## 兼容性状态标签

- `self_contained`
  - 历史节点接近自包含，可优先尝试直接重跑
- `branch_bundle`
  - 需要同阶段的一组 MATLAB 依赖文件，不应只恢复单文件
- `external_pann`
  - 依赖共享 `PANN_Holography.py` 和 `target_for_python.mat -> dl_phase_init.mat` 中转契约
- `needs_audit`
  - 当前 `src/` 仅为占位快照，不能视为最终可运行组合

## 1. `cc3dced2` 相位反演起点

- 目录：`01_hologram_phase_recovery__IASA_0221_cc3dced2`
- `milestone_commit`：`cc3dced24c06b0ad394da86e7ed49562126ed7da`
- 主题：IASA 0221 版本，相位反演早期基线
- 当前状态：`self_contained`
- 当前主入口：`HDSP_debug0209.m`
- 当前 `src/` 用途：
  - 可作为首轮直接重跑候选
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
  - 对应任务书中的迭代相位恢复起点
  - 为后续相位优化提供原始基线

## 2. `a4a3cd8e` 相位板结构映射

- 目录：`02_phase_board_mapping__thickness_built_a4a3cd8e`
- `milestone_commit`：`a4a3cd8e69cb2bc139baf2601c5f2722f7b74f4c`
- 主题：`thickness_built` 相位板厚度构建
- 当前状态：`self_contained`
- 当前主入口：`thickness_built.m`
- 当前 `src/` 用途：
  - 可作为首轮直接重跑候选
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
  - 对应任务书中的相位板微观结构映射
  - 是从理想相位走向可制造结构的关键节点

## 3. `dc6d9f95` 早期热固化闭环

- 目录：`03_thermal_closure__temp_curing_dc6d9f95`
- `milestone_commit`：`dc6d9f95a8f88942347e9fd94ba5359ac6e03217`
- 主题：引入温度固化的早期闭环
- 当前状态：`branch_bundle`
- 当前主入口：`tempdebug.m`
- 当前 `src/` 用途：
  - 仅代表当前已识别到的首选入口
  - 不保证单文件即可运行
- 运行组合策略：
  - 优先以 `tempdebug.m` 为主
  - 视缺失函数或变量，再补同阶段 `HDSPdebug.m` 或同目录依赖
- 建议导出图表：
  - 目标图案与最佳焦面声压图
  - Z-scan 曲线
  - 温度场图
  - 基于阈值的固化或空化覆盖图
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

## 4. `2a953a3b` Arrhenius 热剂量节点

- 目录：`04_arrhenius_thermal_dose__2a953a3b`
- `milestone_commit`：`2a953a3b2c7af09f6e28fc91c63f1519cc7f7fa4`
- 主题：Arrhenius 动力学引擎与动态声热耦合
- 当前状态：`branch_bundle`
- 当前主入口：`tempdebug.m`
- 当前 `src/` 用途：
  - 代表当前已识别到的同阶段文件集合
  - 不代表已经过完整兼容性核对
- 运行组合策略：
  - 以 `tempdebug.m` 为首选运行入口
  - `HDSPdebug.m`、`IASAdebug.m`、`PANN_Holography.py` 仅表示该阶段已出现相关模块
  - 需要逐项核对是否真实构成该节点的可运行组合
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
  - 这是从温度阈值后处理升级为动力学固化评估的关键节点

## 5. `79d204af` Python/PANN 相位优化转折

- 目录：`05_python_pann_phase_optimization__79d204af`
- `milestone_commit`：`79d204afb3ab19a5ae773a8f2d67e0f8aafef965`
- 主题：PANN 主导 IASA
- 当前状态：`external_pann` + `needs_audit`
- 当前主入口：`HDSPdebug.m`
- 关键事实：
  - 该提交的 tree 中没有 `PANN_Holography.py`
  - `HDSPdebug.m` 明确依赖 `C:\Users\Zh89\Desktop\transport`
  - 运行契约是 `target_for_python.mat -> dl_phase_init.mat`
- 当前 `src/` 用途：
  - 只能作为历史节点说明
  - 不能视为可直接运行环境
- 运行组合策略：
  - 必须单独确定与该节点兼容的 `PANN_Holography.py` 版本
  - 必须保留 MATLAB 暂停、手动运行 Python、再回 MATLAB 的中转流程
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
  - 这是相位求解从传统 IASA 转向 Python/PANN 引导优化的关键转折

## 6. `7ef8144b` 出口复场诊断

- 目录：`06_exit_field_diagnostics__7ef8144b`
- `milestone_commit`：`7ef8144be47c2604157143d5ca97d9af611c21fc`
- 主题：出口平面复场分析
- 当前状态：`external_pann` + `branch_bundle`
- 当前主入口：`HDSPdebug.m`
- 当前 `src/` 用途：
  - 代表该阶段已知的核心 MATLAB 依赖
  - `PANN_Holography.py` 仍需确认是否与该 MATLAB 入口严格匹配
- 运行组合策略：
  - 除 MATLAB 文件外，还要核对共享 PANN 脚本版本
  - 不能把“同提交带了 PANN”直接等同于“与该节点入口兼容”
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
  - 它解释了理想相位与真实厚板输出之间的失配来源

## 7. `35df2a62` 空化剂量主导固化

- 目录：`07_cavitation_dose_curing__35df2a62`
- `milestone_commit`：`35df2a62c7f26e3b78232c6ed4dcc02ca5565f96`
- 主题：空化云一致性剂量
- 当前状态：`external_pann` + `branch_bundle`
- 当前主入口：`HDSPdebug.m`
- 当前 `src/` 用途：
  - 表示空化固化阶段的关键 MATLAB 依赖已经初步归拢
  - 但仍保留共享 PANN 中转依赖
- 已确认特征：
  - `HDSPdebug.m` 明确写入 `target_for_python.mat`
  - 再读取 `dl_phase_init.mat`
  - 说明仍遵守共享 PANN 中转契约
- 运行组合策略：
  - MATLAB 主入口可先按当前 bundle 审核
  - PANN 版本仍需单独做兼容性确认
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
  - 这是 PDMS 类材料由热主导转向空化主导的决定性节点

## 8. `5e2692a0` 三材料并列固化系统

- 目录：`08_multi_material_cure_profiles__5e2692a0`
- `milestone_commit`：`5e2692a040916cdab672ad984abb889f27415435`
- 主题：材料配套的三套固化系统
- 当前状态：`branch_bundle`
- 当前主入口：
  - `run_cure_system_profile_suite.m`
  - `simulate_cure_from_pressure_map.m`
- 当前 `src/` 用途：
  - 更接近一个可审计的模块化运行集合
  - 但仍需实际执行验证
- 已确认特征：
  - `run_cure_system_profile_suite.m` 显式依赖
    - `build_cure_system_profile`
    - `build_pressure_validation_cases`
    - `simulate_cure_from_pressure_map`
  - 说明该节点天然应按模块 bundle 而不是单文件恢复
- 建议导出图表：
  - 三个 profile 的 cured mask 对比图
  - 三个 profile 的 score / 温升 / 风险图对比
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
  - 这是当前项目架构最完整、最适合作任务书收束表达的节点

## 当前结论

### 可优先直接尝试的节点

- `cc3dced2`
- `a4a3cd8e`

### 应按 MATLAB bundle 核查后再跑的节点

- `dc6d9f95`
- `2a953a3b`
- `5e2692a0`

### 必须把共享 PANN 中转作为显式依赖处理的节点

- `79d204af`
- `7ef8144b`
- `35df2a62`

## 下一步执行顺序

1. 先完成各节点 `runtime_bundle` 兼容性审计
2. 将现有 `src/` 标记为“占位快照”或“候选运行组合”
3. 优先重跑 `cc3dced2`、`a4a3cd8e`
4. 再处理 `dc6d9f95`、`2a953a3b`、`5e2692a0`
5. 最后单独核定 PANN 兼容版本，再进入 `79d204af`、`7ef8144b`、`35df2a62`
