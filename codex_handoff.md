项目目标：

基于 k-Wave 的相位调制板超声面打印仿真。
关注指标：PCC / SSIM / NMSE / EE / IoU / Dice / Over-cure / Under-cure。
当前核心问题不是热参数扫不出来，而是前向设计模型和真实 k-Wave 传播之间有明显域偏差。
当前代码结构判断：

MATLAB 主流程在 HDSPdebug.m。
Python 全息优化在 PANN_Holography.py。
当前保留的诊断重点是三焦面对照：
Python ASM
IASA ASM
k-Wave Focal
已经验证过的结论：

python_only 效果差于 python_iasa。
IASA 不是主问题，当前它对结果有正贡献。
锚定式 IASA（把结果往 Python 初值拉回）会系统性变差。
Python 和 IASA 在 ASM 模型内都能得到较高相似度，但到 k-Wave 焦面后明显退化。
因此主瓶颈是：
ASM / 理想相位屏
到
3D 厚板 + 离散体素 + k-Wave FDTD
之间的模型失配。
做过并验证效果不佳或失败的路线：

热计量主导损失、量化感知、空间抖动已接入过。
k-Wave 外环反馈路线已测试，结果负收益，已回退。
锚定 IASA 路线已测试，结果负收益，已放弃。
当前建议保留的基线：

phase_refine_mode = 'python_iasa'
使用三焦面对照继续做诊断
不使用 k-Wave 外环反馈
更可能有效的下一步方向：

不再折腾 k-Wave 外环
优先缩小前向模型偏差
重点考虑“离散厚度级的有效复透射模型”而不是纯相位屏模型
当前回退状态：

已回退到三焦面对照版本
已删除外环反馈辅助文件
主脚本可直接继续运行