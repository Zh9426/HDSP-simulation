# Runtime Compatibility Audit

本文件用于纠正一个关键误区：

“历史重要提交”不等于“可以直接拿来跑的完整源码快照”。

在本仓库里，至少存在三种不同层级的运行依赖：

## 1. 单脚本自包含层

特点：

- 主入口几乎独立
- 同提交内依赖很少
- 可直接做首轮重跑尝试

当前候选：

- `cc3dced2`
- `a4a3cd8e`

## 2. 同阶段 MATLAB bundle 层

特点：

- 主入口只是调度脚本
- 需要同阶段多份 `.m` 文件配套
- 恢复单一脚本通常不够

当前候选：

- `dc6d9f95`
- `2a953a3b`
- `5e2692a0`

## 3. 共享 PANN 手动中转层

特点：

- MATLAB 写出 `target_for_python.mat`
- 人工运行 `PANN_Holography.py`
- MATLAB 再读回 `dl_phase_init.mat`
- PANN 与 MATLAB 脚本是共同演化的，不能跨版本随意拼接

当前候选：

- `79d204af`
- `7ef8144b`
- `35df2a62`

## 已确认的根因证据

### `79d204af`

- `HDSPdebug.m` 明确硬编码 `C:\Users\Zh89\Desktop\transport`
- 依赖 `target_for_python.mat`
- 依赖 `dl_phase_init.mat`
- 该提交 tree 本身没有 `PANN_Holography.py`

结论：

- 它是“历史里程碑提交”
- 不是“可直接运行的自包含快照”

### `35df2a62`

- `HDSPdebug.m` 仍然写出 `target_for_python.mat`
- 然后读取 `dl_phase_init.mat`

结论：

- 即使 MATLAB 依赖文件已经比较完整，仍不能把共享 PANN 依赖忽略掉

## 对当前分支中 `src/` 的解释

当前各节点 `src/` 的作用是：

- 固定历史锚点
- 汇总候选运行文件
- 为后续兼容性核查提供工作底稿

当前各节点 `src/` 不是：

- 已验证可直接运行的最终环境
- 已完成版本适配的正式重跑代码包

## 后续整理原则

1. 每个节点都要单独填写 `runtime_bundle`
2. 对共享 PANN 节点，必须明确：
   - 使用哪个 `PANN_Holography.py`
   - MATLAB 输出哪些字段
   - Python 读取和写回哪些字段
3. 若历史节点只能通过“相邻兼容版本组合”重跑，必须在节点说明里显式记录
4. 不再声称“源码来自该提交本身即可运行”，除非已实际验证
