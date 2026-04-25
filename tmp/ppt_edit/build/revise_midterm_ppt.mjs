import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, PresentationFile } from "@oai/artifact-tool";

const INPUT_PPT = "F:/GitHub/HDSP-simulation/tmp/ppt_edit/中期报告.pptx";
const OUTPUT_PPT = "F:/GitHub/HDSP-simulation/tmp/ppt_edit/中期报告_修订版.pptx";
const PREVIEW_DIR = "F:/GitHub/HDSP-simulation/tmp/ppt_edit/preview";

const IMG_PANN = "C:/Users/Zh89/.codex/generated_images/019da624-7a13-7f80-b66b-b20a8486cdc5/ig_05baa7a5468b50040169e5ce60b0188197894d3a6012993253.png";
const IMG_FLOW = "C:/Users/Zh89/.codex/generated_images/019da624-7a13-7f80-b66b-b20a8486cdc5/ig_05baa7a5468b50040169e5d4bce6888197a6b82f7e24da1c6e.png";

const COLOR = {
  navy: "#284E79",
  blue: "#4B6F9C",
  lightBlue: "#EAF1F9",
  pale: "#F7FAFD",
  border: "#C8D5E6",
  text: "#1F2F43",
  muted: "#5D718A",
  green: "#E9F6EF",
  amber: "#FFF4E5",
  red: "#FCEBEC",
  greenHead: "#2F7D57",
  amberHead: "#C58522",
  redHead: "#B34747",
};

async function readImageBlob(imagePath) {
  const bytes = await fs.readFile(imagePath);
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

async function saveMaybeBlob(result, outPath) {
  if (result && typeof result.save === "function") {
    await result.save(outPath);
    return;
  }
  if (result instanceof Uint8Array) {
    await fs.writeFile(outPath, result);
    return;
  }
  if (result instanceof ArrayBuffer) {
    await fs.writeFile(outPath, new Uint8Array(result));
    return;
  }
  if (result && typeof result.arrayBuffer === "function") {
    const buf = await result.arrayBuffer();
    await fs.writeFile(outPath, new Uint8Array(buf));
    return;
  }
  throw new Error(`Unsupported export result for ${outPath}`);
}

function shapeText(shape) {
  try {
    return String(shape.text ?? "");
  } catch {
    return "";
  }
}

function preserveTitle(slide, titleKeyword) {
  for (const shape of slide.shapes.items) {
    const text = shapeText(shape);
    if (text.includes(titleKeyword)) {
      return shape;
    }
  }
  return null;
}

function clearSlide(slide, keepKeywords = []) {
  for (const shape of [...slide.shapes.items]) {
    const text = shapeText(shape);
    if (keepKeywords.some((keyword) => text.includes(keyword))) continue;
    shape.delete();
  }
  for (const image of [...(slide.images?.items ?? [])]) {
    try {
      image.width = 0;
      image.height = 0;
    } catch {}
  }
}

function setTitle(shape, text) {
  if (!shape) return;
  shape.text = text;
  shape.text.fontSize = 30;
  shape.text.bold = true;
  shape.text.color = COLOR.navy;
  shape.text.typeface = "Microsoft YaHei";
}

function addPanel(slide, { left, top, width, height, title, fill = COLOR.pale, titleFill = COLOR.navy }) {
  const panel = slide.shapes.add({
    geometry: "roundRect",
    position: { left, top, width, height },
    fill,
    line: { width: 1.2, fill: COLOR.border },
  });
  const header = slide.shapes.add({
    geometry: "roundRect",
    position: { left: left + 14, top: top + 12, width: width - 28, height: 42 },
    fill: titleFill,
    line: { width: 0, fill: titleFill },
  });
  header.text = title;
  header.text.fontSize = 21;
  header.text.bold = true;
  header.text.color = "#FFFFFF";
  header.text.alignment = "center";
  header.text.verticalAlignment = "middle";
  header.text.typeface = "Microsoft YaHei";
  return { panel, header };
}

function addTextbox(slide, { left, top, width, height, text, fontSize = 18, color = COLOR.text, bold = false, align = "left", fill = null }) {
  const box = slide.shapes.add({
    geometry: "roundRect",
    position: { left, top, width, height },
    fill: fill ?? "#FFFFFF00",
    line: { width: fill ? 1 : 0, fill: fill ? COLOR.border : "#FFFFFF00" },
  });
  box.text = text;
  box.text.fontSize = fontSize;
  box.text.color = color;
  box.text.bold = bold;
  box.text.typeface = "Microsoft YaHei";
  box.text.alignment = align;
  box.text.verticalAlignment = "middle";
  box.text.insets = { left: 16, right: 16, top: 10, bottom: 10 };
  return box;
}

function addBulletCard(slide, cfg) {
  addPanel(slide, cfg);
  const box = addTextbox(slide, {
    left: cfg.left + 18,
    top: cfg.top + 70,
    width: cfg.width - 36,
    height: cfg.height - 88,
    text: cfg.text,
    fontSize: 18,
    color: COLOR.text,
  });
  box.text.alignment = "left";
  return box;
}

const pptx = await FileBlob.load(INPUT_PPT);
const presentation = await PresentationFile.importPptx(pptx);

const slide8 = presentation.slides.getItem(7);
const slide9 = presentation.slides.getItem(8);
const slide10 = presentation.slides.getItem(9);
const slide11 = presentation.slides.getItem(10);

clearSlide(slide8, ["阶段5"]);
setTitle(preserveTitle(slide8, "阶段5"), "阶段5：MATLAB + Python 混合优化主线形成");
addTextbox(slide8, {
  left: 92,
  top: 118,
  width: 1736,
  height: 54,
  text: "Python 负责量化感知初相优化，MATLAB 负责 IASA 细化、离散板投影与 k-Wave / 热固化主线验证。",
  fontSize: 20,
  color: COLOR.muted,
  align: "center",
});
addPanel(slide8, {
  left: 92,
  top: 190,
  width: 1736,
  height: 810,
  title: "PANN_Holography.py 在混合优化主线中的职责",
});
slide8.images.add({
  blob: await readImageBlob(IMG_PANN),
  fit: "contain",
  alt: "PANN架构图",
}).position = { left: 130, top: 270, width: 1660, height: 600 };
addTextbox(slide8, {
  left: 150,
  top: 875,
  width: 520,
  height: 88,
  text: "输入：目标图案、提前腐蚀目标图案与物理参数\n输出：optimal_initial_phase、optimal_layer_map、phase_step",
  fontSize: 17,
  fill: "#FFFFFF",
});
addTextbox(slide8, {
  left: 710,
  top: 875,
  width: 430,
  height: 88,
  text: "核心机制：热剂量感知目标整形 + ASM传播 + STE量化 + 多项损失联合优化",
  fontSize: 17,
  fill: "#FFFFFF",
});
addTextbox(slide8, {
  left: 1180,
  top: 875,
  width: 580,
  height: 88,
  text: "与 MATLAB 的接口：target_for_python.mat -> dl_phase_init.mat\n为后续 IASA 细化提供可制造的初始相位与离散层信息",
  fontSize: 17,
  fill: "#FFFFFF",
});

clearSlide(slide9, ["当前总览"]);
setTitle(preserveTitle(slide9, "当前总览"), "当前总览");
addTextbox(slide9, {
  left: 92,
  top: 118,
  width: 1736,
  height: 54,
  text: "主线已经形成从设计输入、相位优化、离散板构建、三维传播、出口诊断到热固化评估的闭环流程。",
  fontSize: 20,
  color: COLOR.muted,
  align: "center",
});
addPanel(slide9, {
  left: 70,
  top: 190,
  width: 1780,
  height: 770,
  title: "HDSP 当前版本完整逻辑示意图",
});
slide9.images.add({
  blob: await readImageBlob(IMG_FLOW),
  fit: "contain",
  alt: "HDSP完整逻辑图",
}).position = { left: 120, top: 240, width: 1680, height: 650 };
slide9.shapes.add({
  geometry: "rect",
  position: { left: 0, top: 860, width: 1920, height: 220 },
  fill: "#FFFFFF",
  line: { width: 0, fill: "#FFFFFF" },
});
addTextbox(slide9, {
  left: 210,
  top: 890,
  width: 1460,
  height: 58,
  text: "主链路：目标图案与热预补偿 -> Python 初相 -> MATLAB IASA + 离散板投影 -> k-Wave 声场 -> 出口分析 -> 热场/固化预测 -> 指标输出",
  fontSize: 18,
  color: COLOR.text,
  align: "center",
  fill: "#FFFFFF",
});

clearSlide(slide10, ["阶段6"]);
setTitle(preserveTitle(slide10, "阶段6"), "阶段6：后续增强与支线探索");
addTextbox(slide10, {
  left: 92,
  top: 118,
  width: 1736,
  height: 68,
  text: "演进主旨：从“只看焦平面像不像”转向“直接分析厚板出口复场”，并探索数据驱动代理模型以降低诊断成本。",
  fontSize: 20,
  color: COLOR.muted,
  align: "center",
});
addPanel(slide10, {
  left: 82,
  top: 215,
  width: 810,
  height: 720,
  title: "探索1：出口平面复场诊断（物理层）",
});
addTextbox(slide10, {
  left: 120,
  top: 300,
  width: 734,
  height: 110,
  text: "不再仅观测焦平面，而是在厚板出口处直接截取复场，恢复出口幅值与相位，并与理论相位板进行对齐比较。",
  fontSize: 19,
  fill: "#FFFFFF",
});
const steps1 = [
  "记录出口平面时序信号 p(t)",
  "复数解调恢复 p_exit_complex",
  "得到出口幅值、出口相位",
  "计算相位残差与 mean / RMS / max 误差",
  "分析厚度、梯度、边缘距离与出口幅值的相关性",
];
steps1.forEach((text, idx) => {
  const top = 435 + idx * 88;
  const badge = slide10.shapes.add({
    geometry: "ellipse",
    position: { left: 132, top, width: 38, height: 38 },
    fill: COLOR.blue,
    line: { width: 0, fill: COLOR.blue },
  });
  badge.text = String(idx + 1);
  badge.text.fontSize = 18;
  badge.text.bold = true;
  badge.text.color = "#FFFFFF";
  badge.text.alignment = "center";
  badge.text.verticalAlignment = "middle";
  badge.text.typeface = "Microsoft YaHei";
  addTextbox(slide10, {
    left: 186,
    top: top - 10,
    width: 640,
    height: 58,
    text,
    fontSize: 18,
    fill: "#FFFFFF",
  });
});

addPanel(slide10, {
  left: 954,
  top: 215,
  width: 874,
  height: 720,
  title: "探索2：出口幅值代理模型（数据层）",
});
addTextbox(slide10, {
  left: 990,
  top: 300,
  width: 802,
  height: 110,
  text: "尝试 Data-driven 范式，从局部厚度及统计特征学习真实出口幅值响应，目标是在保持诊断趋势的同时替代部分耗时的全波仿真。",
  fontSize: 19,
  fill: "#FFFFFF",
});
const flowX = [1025, 1185, 1345, 1505, 1665];
const flowTitles = ["厚度与局部特征", "样本抽取", "代理模型训练", "出口幅值预测", "与全波结果对照"];
flowTitles.forEach((title, idx) => {
  const card = slide10.shapes.add({
    geometry: "roundRect",
    position: { left: flowX[idx], top: 500, width: 118, height: 142 },
    fill: idx === flowTitles.length - 1 ? COLOR.green : "#FFFFFF",
    line: { width: 1.2, fill: COLOR.border },
  });
  card.text = title;
  card.text.fontSize = 18;
  card.text.bold = true;
  card.text.color = COLOR.text;
  card.text.alignment = "center";
  card.text.verticalAlignment = "middle";
  card.text.typeface = "Microsoft YaHei";
  if (idx < flowTitles.length - 1) {
    slide10.shapes.add({
      geometry: "rightArrow",
      position: { left: flowX[idx] + 124, top: 547, width: 34, height: 36 },
      fill: COLOR.blue,
      line: { width: 0, fill: COLOR.blue },
    });
  }
});
addTextbox(slide10, {
  left: 1010,
  top: 705,
  width: 764,
  height: 150,
  text: "这一支线的定位不是替代主线，而是为出口诊断提供更快的近似工具：\n1）帮助识别厚板与理想相位屏之间的系统失配；\n2）为后续参数扫描与代理建模打基础。",
  fontSize: 18,
  fill: "#FFFFFF",
});

clearSlide(slide11, ["当前成果"]);
setTitle(preserveTitle(slide11, "当前成果"), "当前成果、存在问题与下一步计划");
addTextbox(slide11, {
  left: 92,
  top: 118,
  width: 1736,
  height: 70,
  text: "中期目标已按计划完成，当前主线已经形成可运行、可评估、可诊断的全流程闭环；下阶段重心转向参数收敛、对比实验与论文表达。",
  fontSize: 20,
  color: COLOR.muted,
  align: "center",
});
addBulletCard(slide11, {
  left: 96,
  top: 235,
  width: 520,
  height: 620,
  title: "已完成核心里程碑",
  titleFill: COLOR.greenHead,
  fill: COLOR.green,
  text: "• 打通从目标图案到热固化评价的全物理闭环\n\n• 确立 MATLAB + Python 跨平台协同架构\n\n• 累积多轮迭代、具备完整证据链的量化对比结果\n\n• 形成可汇报的主线流程、图示与指标体系",
});
addBulletCard(slide11, {
  left: 700,
  top: 235,
  width: 520,
  height: 620,
  title: "当前存在问题",
  titleFill: COLOR.redHead,
  fill: COLOR.red,
  text: "• 离散厚度板与最终热固化结果之间仍存在耦合误差\n\n• 多目标指标之间存在拉扯，尚未确定统一全局最优判据\n\n• ASM 到 k-Wave 之间仍有显著性能退化，需要更强物理诊断",
});
addBulletCard(slide11, {
  left: 1304,
  top: 235,
  width: 520,
  height: 620,
  title: "下一步行动计划",
  titleFill: COLOR.amberHead,
  fill: COLOR.amber,
  text: "• 冻结并稳固当前主线，统一全部对比实验口径\n\n• 补全关键消融数据与定量对比（Ablation Study）\n\n• 将系统演化成果沉淀为论文的方法与实验章节\n\n• 继续完善出口诊断与代理模型支线",
});
addTextbox(slide11, {
  left: 170,
  top: 895,
  width: 1580,
  height: 90,
  text: "中期阶段的核心结论是：主线框架已经封顶，后续工作的重点不再是“能不能跑通”，而是“如何做得更稳、更准、更可解释”。",
  fontSize: 21,
  color: COLOR.text,
  bold: true,
  align: "center",
  fill: "#FFFFFF",
});

await fs.mkdir(PREVIEW_DIR, { recursive: true });
for (const slideIndex of [7, 8, 9, 10]) {
  const slide = presentation.slides.getItem(slideIndex);
  const png = await presentation.export({ slide, format: "png", scale: 1 });
  await saveMaybeBlob(png, path.join(PREVIEW_DIR, `slide-${slideIndex + 1}.png`));
}

const out = await PresentationFile.exportPptx(presentation);
await out.save(OUTPUT_PPT);
console.log(OUTPUT_PPT);
