# 相位板构建方式对比

本目录用于比较三种相位板构建路径在真实相位板 k-Wave 仿真中的声场调制效果。当前脚本只分析声压分布，不进入固化预测。

## 主程序

- `compare_phase_board_construction_methods.m`

三种模式：

1. `direct_discrete_from_biasa_initial`：先用连续 WIASA/BIASA 思路求一个初相，再一次性离散成相位板。
2. `python_iasa_inloop_board`：使用 Python 初相，再按 `IASAdebug0420.m` 的方式在 IASA 迭代内投影相位板。
3. `pure_biasa_inloop_board`：丢弃 Python，直接从随机相位进入板约束 BIASA 迭代内构建。

## Python 初相

`helpers/PANN_Holography.py` 和 `helpers/pann_quality_metrics.py` 来自 `codex/initial-phase-study` 分支的稳定 transport 流程。MATLAB 脚本会写出：

- `C:\Users\Zh89\Desktop\transport\target_for_python.mat`

然后暂停。此时在 PowerShell 中运行脚本打印出的 Python 命令，生成：

- `C:\Users\Zh89\Desktop\transport\dl_phase_init.mat`

回到 MATLAB 按任意键继续。

## 输出

运行后输出写入本目录的 `outputs/`，该目录被局部 `.gitignore` 忽略，不纳入提交。

主要输出：

- `board_construction_comparison_results.mat`：完整结果结构，包含三种模式的相位、层数、厚度、出口复声场、目标平面声压等矩阵。
- `summary.txt` / `summary.json`：简要指标。
- `metrics_table.csv`：便于表格分析的指标。
- `board_construction_overview.png`：目标、厚度、出口幅值、目标平面声压总览。
- `centerline_comparison.png`：目标平面中心线对比。

可选环境变量：

- `HDSP_BOARD_COMPARE_NX`：网格尺寸，默认 `512`。
- `HDSP_BOARD_COMPARE_MAIN_EPOCHS`：Python+IASA 迭代次数，默认 `150`。
- `HDSP_BOARD_COMPARE_BIASA_EPOCHS`：纯 BIASA 迭代次数，默认 `450`。
- `HDSP_BOARD_COMPARE_RUN_PYTHON_CASE`：是否运行 Python+IASA 模式，默认 `1`。
- `HDSP_BOARD_COMPARE_REUSE_PYTHON_OUTPUT`：是否复用已有 `dl_phase_init.mat`，默认 `0`。
- `HDSP_BOARD_COMPARE_SCAN_OFFSETS_MM`：目标平面扫描偏移，默认 `0`。例如 `-1,-0.5,0,0.5,1`。
- `HDSP_BOARD_COMPARE_DRY_RUN`：只验证构建和输出，不运行 k-Wave，默认 `0`。
