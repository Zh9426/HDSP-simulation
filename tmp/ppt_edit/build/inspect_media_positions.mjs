import { FileBlob, PresentationFile } from "@oai/artifact-tool";
const pptx = await FileBlob.load("F:/GitHub/HDSP-simulation/tmp/ppt_edit/中期报告.pptx");
const pres = await PresentationFile.importPptx(pptx);
for (const idx of [7,8,9,10]) {
  const slide = pres.slides.getItem(idx);
  console.log('slide', idx+1);
  const imgs = slide.images?.items ?? [];
  console.log('images', imgs.length);
  for (const img of imgs.slice(0,10)) console.log(JSON.stringify(img.position));
}
