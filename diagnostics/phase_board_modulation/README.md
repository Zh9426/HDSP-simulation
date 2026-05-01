# 相位板调制诊断分支说明

本分支用于基于 `IASAdebug0420.m` 继续诊断相位板离散调制对焦场质量的影响。

## 基线脚本

- 原始脚本来源：`F:\MATLAB\code\HDSP\IASAdebug\IASAdebug0420.m`
- 分支内基线副本：`diagnostics/phase_board_modulation/IASAdebug0420_baseline.m`

## 已确认的代码结构

`IASAdebug0420` 当前主要做三组相位方案对照：

1. Python 初始相位投影到离散板层。
2. Python 初始相位再经过 IASA 迭代细化。
3. 从随机相位出发的 Pure IASA。

脚本先用 ASM 估计焦平面，再用均匀水中的 direct-phase k-Wave 做验证。这里的 k-Wave 阶段明确没有构建真实厚度板，而是把相位图直接作为源面相位边界条件。

## 与之前讨论结果的衔接

之前已经确认，当前主线相位板构建不应再按旧的“连续厚度 -> 高斯平滑 -> 最后 round 离散化”理解。更准确的链路是：

`连续相位候选 -> project_phase_to_board -> 离散层数 net_num_board -> thickness = net_num_board * dz`

并且这个离散投影在 IASA 迭代内部反复执行，而不是只在最终厚度图上做一次后处理。

## 本分支首要任务

1. 把 direct-phase 诊断和真实厚度板传播诊断分开，避免把“理想相位边界有效”误判成“相位板调制有效”。
2. 输出相位投影误差、层数分布、相位偏置、ASM 指标、direct-phase k-Wave 指标，后续再加真实板传播指标。
3. 检查 Python 初相位、Python+IASA、Pure IASA 三条路径中，离散投影到底改善还是破坏了目标焦场。
4. 保持 IoU/PCC/SSIM/NMSE/能量效率等指标可对照，先诊断调制链路，不急着改固化模型。

## 提交约定

后续每次修改都提交中文 commit。小改用简短提交信息；大改用详细提交说明，明确改动动机、实现点和验证结果。
