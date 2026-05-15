from __future__ import annotations

import subprocess
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAPER = ROOT / "paper"


def git(args: list[str]) -> str:
    return subprocess.check_output(
        ["git", *args],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


@dataclass
class Commit:
    sha: str
    date: str
    refs: str
    subject: str


def collect_commits() -> list[Commit]:
    raw = git(["log", "--all", "--date=short", "--pretty=format:%H%x09%ad%x09%D%x09%s"])
    seen = set()
    commits: list[Commit] = []
    for line in raw.splitlines():
        parts = line.split("\t", 3)
        if len(parts) != 4:
            continue
        sha, date, refs, subject = parts
        if sha in seen:
            continue
        seen.add(sha)
        commits.append(Commit(sha, date, refs, subject))
    return commits


def collect_branches() -> list[dict[str, str]]:
    raw = git(
        [
            "for-each-ref",
            "--format=%(refname:short)|%(objectname)|%(committerdate:short)|%(subject)",
            "refs/heads",
            "refs/remotes",
        ]
    )
    rows = []
    for line in raw.splitlines():
        parts = line.split("|", 3)
        if len(parts) != 4:
            continue
        name, sha, date, subject = parts
        if name == "origin/HEAD":
            continue
        rows.append({"name": name, "sha": sha, "date": date, "subject": subject})
    return rows


def categorize(subject: str) -> str:
    s = subject.lower()
    if any(k in s for k in ["sono", "kuang", "材料", "三套固化", "system profile"]):
        return "材料配套固化系统"
    if any(k in s for k in ["空化", "cavitation", "固化", "cure", "thermal", "阿伦尼乌斯"]):
        return "固化预测/声空化"
    if any(k in s for k in ["初相", "pann", "iasa", "gd-holo", "python", "相位优化"]):
        return "初相/相位计算"
    if any(k in s for k in ["相位板", "厚度", "板约束", "thickness", "离散"]):
        return "相位板构建"
    if any(k in s for k in ["出口", "exit", "surrogate", "代理", "复场", "调制"]):
        return "出口面诊断/代理模型"
    if any(k in s for k in ["报告", "归档", "docs", "paper", "审阅", "summary"]):
        return "报告归档/论文准备"
    if any(k in s for k in ["app", "engine", "mlapp"]):
        return "应用界面/工程封装"
    return "主流程维护/其它"


def branch_role(name: str, subject: str) -> str:
    n = name.lower()
    subj = subject.lower()
    if "cure-analysis" in n:
        return "声空化/材料固化系统分析分支"
    if "initial-phase-study" in n:
        return "初相与相位计算研究分支"
    if "phase-board-modulation-diagnosis" in n:
        return "相位板构建与出口调制诊断分支"
    if "managed-report-audit-clean" in n:
        return "按论文模块归档的历史代码索引分支"
    if "codex_managed" in n or "claude_managed" in n:
        return "主流程归档、报告与稳定快照分支"
    if n.endswith("main") or n == "origin":
        return "早期远端主线，含出口平面复场诊断合并点"
    if "thickness" in n:
        return "厚度映射/相位板构建早期分支"
    if "iasa" in n:
        return "IASA 与 Python 相位优化早期分支"
    if "hdsp" in n:
        return "HDSP 主脚本早期演化分支"
    if "temp" in n:
        return "温度场/热扩散早期分支"
    if "app" in n:
        return "App/工程界面封装分支"
    if "prism" in n:
        return "论文格式与写作约束分支"
    if "rebuilt" in n:
        return "自动化分析输出和重建工作分支"
    if "1111" in n:
        return "三月底/四月初混合主线延伸分支"
    if "pdms" in subj:
        return "PDMS 相关尝试节点"
    return "其它历史/备份分支"


def short(sha: str) -> str:
    return sha[:8]


def make_branch_table(branches: list[dict[str, str]]) -> str:
    lines = ["| 分支 | HEAD | 日期 | 角色判断 | HEAD 说明 |", "| --- | --- | --- | --- | --- |"]
    for b in branches:
        lines.append(
            f"| `{b['name']}` | `{short(b['sha'])}` | {b['date']} | {branch_role(b['name'], b['subject'])} | {b['subject']} |"
        )
    return "\n".join(lines)


def make_stats(commits: list[Commit]) -> tuple[str, str]:
    by_month = Counter(c.date[:7] for c in commits)
    by_cat = Counter(categorize(c.subject) for c in commits)

    month_lines = ["| 月份 | 提交数 |", "| --- | ---: |"]
    for month, count in sorted(by_month.items()):
        month_lines.append(f"| {month} | {count} |")

    cat_lines = ["| 主题 | 提交数 |", "| --- | ---: |"]
    for cat, count in by_cat.most_common():
        cat_lines.append(f"| {cat} | {count} |")
    return "\n".join(month_lines), "\n".join(cat_lines)


def key_commit_table(commits: list[Commit]) -> str:
    keywords = [
        "提交了HDSPdebug的0220版本",
        "提交了IASAdebug的0221版本",
        "tbdebug0223",
        "提交了包含温度固化的版本",
        "feat(thermal)",
        "引入阿伦尼乌斯",
        "改为由Python进行PANN主导的IASA",
        "GD-Holo",
        "新增了出口平面复场分析",
        "PDMS",
        "重构空化",
        "空化剂量",
        "三套固化系统",
        "Kuang",
        "初相",
        "相位板构建方式对比",
    ]
    selected = []
    for c in sorted(commits, key=lambda x: x.date):
        if any(k.lower() in c.subject.lower() for k in keywords):
            selected.append(c)
    lines = ["| 日期 | 提交 | 主题 | 归类 |", "| --- | --- | --- | --- |"]
    for c in selected:
        lines.append(f"| {c.date} | `{short(c.sha)}` | {c.subject} | {categorize(c.subject)} |")
    return "\n".join(lines)


def write_full_commit_index(commits: list[Commit]) -> Path:
    path = PAPER / "git_history_full_index.md"
    lines = [
        "# Git 完整提交索引",
        "",
        "该索引由本地仓库 `git log --all` 生成，用于追溯所有当前可见提交。主叙事见 `project_development_history.md`。",
        "",
        "| 日期 | 提交 | 归类 | refs | 说明 |",
        "| --- | --- | --- | --- | --- |",
    ]
    for c in sorted(commits, key=lambda x: (x.date, x.sha)):
        refs = c.refs.replace("|", "/")
        lines.append(f"| {c.date} | `{short(c.sha)}` | {categorize(c.subject)} | {refs} | {c.subject} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def write_main_doc(commits: list[Commit], branches: list[dict[str, str]]) -> Path:
    month_stats, category_stats = make_stats(commits)
    doc = f"""# HDSP 项目发展历史与论文写作参考

## 1. 文档目的

本文档面向后续毕业论文写作，用于把 `HDSP-simulation` 仓库中的分支、提交历史和本地整理结论统一成一条可解释的项目发展脉络。这里不把每一次提交都写成流水账，而是按研究问题归并：相位计算、相位板构建、k-Wave 声场、出口面诊断、固化预测、材料配套固化系统和论文归档。

本次扫描基于本地仓库 `F:\\GitHub\\HDSP-simulation` 的当前可见 refs。仓库当前可见提交对象共 `{len(commits)}` 个，分支/远端引用共 `{len(branches)}` 个。执行 `git fetch --all --prune` 时本机 `.git/FETCH_HEAD` 权限受限，因此本文档没有强行改动 Git 状态；若后续远端新增提交，需要在修复权限后重新生成。

配套完整提交索引见 `paper/git_history_full_index.md`。

## 2. 总体结论

项目主线可以概括为：

```text
目标图案/打印任务
-> 初相与相位反演
-> 相位板离散构建
-> k-Wave 声场仿真
-> 出口面/焦面诊断
-> 并列固化模块评价
-> 论文归档与结果分析
```

中期之前，项目更像一个“全链路原型”：重点是跑通 `目标 -> 相位 -> 调制板 -> k-Wave -> 热固化评价`。中期之后，方向发生了两点重要变化：

1. 固化模块不再被理解为单一路径上的“进化版本”，而是按材料和机理建立的并列模块。
2. 相位计算仍然是持续优化对象，新的工作重点包括纯 Python 初相、BIASA/板约束 IASA、相位板构建方式对比、出口复场诊断和代理模型。

因此论文中不宜写成“固化模块从第二版进化到第三版再进化到声空化版”。更准确的写法是：

```text
水基/热固化材料：热扩散 + Arrhenius 热剂量模块
PDMS 类材料：声空化主导固化模块
sonoink 材料：自增强声热凝胶/固化模块
```

三者是面向不同打印材料和物理机理的并列模型，由统一的声场输入和统一的形貌评价指标连接。

## 3. Git 分支索引

{make_branch_table(branches)}

## 4. 提交统计

### 4.1 按月份统计

{month_stats}

### 4.2 按主题统计

{category_stats}

这些统计说明：仓库在 2026 年 4 月底到 5 月中旬进入高密度收尾整理期，提交主题从早期的单脚本调参，转向“固化模块独立化、材料模型并列化、相位计算专题化、报告归档结构化”。

## 5. 阶段发展历史

### 5.1 起步阶段：HDSP / IASA / thickness 三条早期支线

时间主要集中在 2026-02-21 至 2026-02-23。早期仓库直接把已有本地脚本拆成 `HDSP`、`IASA`、`thickness_built` 等分支。该阶段的核心问题是把主流程拆清楚：

- `HDSP` 负责主控脚本和 k-Wave 声场闭环。
- `IASA` 负责相位反演质量。
- `thickness_built` 负责相位到离散厚度板的映射。

这一时期的意义不在于形成最终算法，而在于识别出项目不是单个脚本，而是由相位反演、相位板物理实现、声场仿真和后处理评价共同构成。

### 5.2 温度固化进入主线：从声场图到热扩散评价

2026-02-27 至 2026-03-07，`temp` 和 `HDSPdebug` 的提交开始引入温度场演化和固化判据。关键节点包括：

- `提交了包含温度固化的版本，IASA与厚度构建使用HDSP0223.2`
- `提交了新的温度演化版本，加入热扩散`
- `target_median_pressure = 2e6; cavitation_limit = 2.0e6; exposure_time = 0.28`

这一阶段的固化预测仍然主要服务于主流程验证。其算法逻辑是从声压场计算产热，再通过热扩散得到温度场，最后按温度阈值或初步固化判据得到固化形貌。它解决了“声场看起来对，但是否能形成打印区域”的问题。

### 5.3 Arrhenius 与混合相位优化：热历史进入评价

2026-03-15 至 2026-03-30，项目进入 MATLAB + Python 混合相位优化阶段，同时热固化评价从温度阈值进一步转向热剂量。关键提交包括：

- `改为由Python进行PANN主导的IASA`
- `引入阿伦尼乌斯，稳定声压与时间解为2.0,0.24s`
- `feat(thermal): 升级 Arrhenius 动力学引擎与动态声-热耦合模型`
- `feat(phys): 实现 3D 非均匀介质热通量散度求解器与能量守恒模型`
- `新增了出口平面复场分析`

这一阶段的技术变化可以概括为两条线：

1. 相位计算从纯 MATLAB IASA 走向 Python 物理传播算子和损失函数工程。
2. 固化评价从“是否超过温度阈值”走向“温度历史驱动的反应剂量积分”。

其中 Arrhenius 模块适合描述水基或热反应主导材料，而不是所有材料的统一固化机理。

### 5.4 出口面诊断与代理模型：解释相位板真实调制失配

2026-03-30 以后，`codex_managed`、`codex/phase-board-modulation-diagnosis` 和相关提交开始围绕出口场、复场、代理模型进行诊断。稳定报告中明确指出，主流程存在设计传播距离和实际最佳焦面距离之间的差异，例如 `16.00 / 18.79 mm` 的焦面偏移。

这一阶段的作用是把误差来源从“最后固化阈值调得不好”中拆出来。项目开始区分：

- 相位设计是否正确；
- 相位板出口复场是否符合预期；
- k-Wave 中真实厚板调制是否引入额外相位/幅值失配；
- 固化模块是否只是放大了前端声场误差。

这对论文很重要，因为它说明后续工作不是盲目调固化阈值，而是在建立可诊断的多模块结构。

### 5.5 声空化主导固化：从后处理补丁到独立固化模块

2026-04-27 至 2026-05-01 是声空化固化模块形成的密集阶段。关键提交包括：

- `feat: add trigger-led cavitation model and gate exit-plane rerun`
- `重构空化触发与热反馈耦合`
- `重构固化判据为空化主导评分`
- `重构空化固化算法：引入空化云一致性剂量`
- `改为空化剂量主导的固化判据`
- `替换主脚本固化判据为空化剂量模型`
- `重构固化模块独立验证主线`

这一阶段的核心结论是：PDMS 类材料的固化不能再简单套用水基热固化/Arrhenius 模块。新的空化模块从声压图中计算空化触发、增长、流致风险、空化剂量和热辅助项，再用 `IoU / Dice / 过固化 / 欠固化 / 覆盖率` 等指标评价固化形貌。

因此，声空化模块不是 Arrhenius 模块的下一代，而是面向另一类材料机理的并列模块。

### 5.6 材料配套三系统：并列固化模型正式成型

2026-05-05，`codex/cure-analysis` 分支把固化模块进一步抽象为材料配套系统。`build_cure_system_profile.m` 中明确给出三套 profile：

- `pdms_cavitation`：PDMS 类材料，声空化主导。
- `water_arrhenius`：水基树脂/热固化材料，热扩散 + Arrhenius。
- `sonoink_self_enhancing`：参考 Kuang 文献的 sonoink，自增强声热凝胶/固化。

`simulate_cure_from_pressure_map.m` 进一步把三类机制统一封装到同一个入口中：

```text
p_amp + exposure_time + params + target_mask
-> simulate_cure_from_pressure_map
-> cure_score / cured_mask / metrics
```

这一步完成了架构层面的转变：固化模块不再是主流程末端写死的一段代码，而是可替换、可验证、可按材料选择的预测模块。

### 5.7 初相与相位板约束继续优化

2026-05-06 至 2026-05-15，项目继续在相位计算方向推进。`codex/initial-phase-study` 明确把研究范围限定为初相计算，并指出该分支停止在压力场分析，不运行固化、厚度板和代理训练。关键方向包括：

- 纯 Python 初相路径；
- 初相三方案声压对比；
- 按固化质量选择初相候选；
- BIASA 优化研究；
- 板约束窄带声压优化；
- Python 迭代中引入板约束投影；
- 强化目标背景分离约束。

这一阶段说明，相位计算不是中期阶段结束后就固定不动，而是继续作为主线优化对象。论文中可以把它写成“相位计算模块持续迭代，为并列固化模块提供更高质量的声场输入”。

## 6. 当前项目架构

当前项目更适合写成如下模块结构：

```text
目标生成层
  - scaffold / A 字目标 / 论文验证目标

相位计算层
  - IASA / WIASA / BIASA
  - Python PANN / GD-Holo / 纯物理传播算子
  - 初相方法对比与压力场指标

相位板构建层
  - wrapped phase 投影
  - 全局相位偏置搜索
  - 误差扩散量化
  - 板约束 IASA / 相位板构建方式对比

声场仿真与诊断层
  - k-Wave 三维传播
  - Z-scan 焦面搜索
  - 出口平面复场分析
  - 出口幅值/复场代理模型

并列固化评价层
  - water_arrhenius
  - pdms_cavitation
  - sonoink_self_enhancing

结果评价层
  - Correlation / NMSE / PSNR
  - EE / sidelobe / uniformity
  - IoU / Dice / over-cure / under-cure / coverage
```

## 7. 固化模块的正确论文表述

建议避免使用“第一版、第二版、第三版逐代替换”的单线叙述。更合理的表述是：

1. 早期为了验证声场能否产生打印形貌，采用过温度阈值和热扩散后处理。
2. 对热反应主导材料，引入 Arrhenius 热剂量模块，使固化评价考虑温度历史。
3. 对 PDMS 类材料，建立声空化主导模块，将空化触发、空化剂量和空化云一致性作为主要固化依据。
4. 对 sonoink，建立自增强声热凝胶模型，参考文献参数重标定材料温升和凝胶动力学。
5. 三类模型并列存在，由材料 profile 决定调用哪一种固化机制。

这种写法可以避免逻辑错误：声空化模块并不是 Arrhenius 的“升级版”，而是材料机理不同导致的另一套预测框架。

## 8. 相位计算模块的论文表述

相位计算可以按“持续优化输入声场质量”来写：

- 早期：IASA/WIASA 用于建立可运行的相位反演。
- 中期：Python 优化器引入热剂量代理、均匀度、背景抑制和能量效率损失。
- 后期：纯 Python 初相、BIASA、板约束投影和相位板构建方式对比，用于解决理想相位与真实离散相位板之间的失配。

论文中建议把相位计算和固化模块分开写。相位计算回答“如何得到目标声场”，固化模块回答“该声场在某类材料中如何转化为固化形貌”。

## 9. 数据与结果锚点

可作为论文或答辩中的结果锚点：

- IASA 早期质量提升：Correlation 从约 `0.8255` 提升到 `0.9189`。
- 厚度量化误差：平均相位量化误差从约 `118.8°` 降至 `7.3°`。
- 0302/0306 热固化主线：IoU 约 `0.8973 / 0.8916`，用于说明热评价闭环已经建立。
- 主流程焦面偏移诊断：设计/最佳距离曾出现约 `16.00 / 18.79 mm` 差异，说明出口面和真实厚板诊断必要。
- 声空化分支：以 `IASAdebug0420_cure_validation.m` 为权威验证入口，输出 `python_iasa_cure_validation.mat` 和固化验证图。
- 材料 profile：`build_cure_system_profile.m` 将 PDMS、水基热固化和 sonoink 三类固化系统显式并列。

## 10. 论文写作建议

建议论文方法章节采用下面结构：

1. 研究对象与全链路框架
2. 目标图案与仿真网格设置
3. 全息相位计算方法
4. 相位调制板离散构建方法
5. k-Wave 声场仿真与出口面诊断
6. 面向不同材料的并列固化预测模型
7. 评价指标与实验对比

其中第 6 节应作为论文的关键创新表达之一。可以命名为“材料配套固化预测模型”，而不是“固化预测模块的最终版本”。

## 11. 关键提交索引

{key_commit_table(commits)}

## 12. 可复核命令

本文件主要依据以下 Git 命令生成和复核：

```powershell
git branch -a --verbose --no-abbrev
git rev-list --all --count
git log --all --date=short --pretty=format:\"%H%x09%ad%x09%D%x09%s\"
git ls-tree -r --name-only <branch>
git show <branch>:<path>
```

"""
    path = PAPER / "project_development_history.md"
    path.write_text(doc, encoding="utf-8")
    return path


def main() -> None:
    PAPER.mkdir(parents=True, exist_ok=True)
    commits = collect_commits()
    branches = collect_branches()
    main_path = write_main_doc(commits, branches)
    index_path = write_full_commit_index(commits)
    print(main_path)
    print(index_path)


if __name__ == "__main__":
    main()
