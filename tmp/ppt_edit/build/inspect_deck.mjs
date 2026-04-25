import { FileBlob, PresentationFile } from "@oai/artifact-tool";
const pptx = await FileBlob.load("F:/GitHub/HDSP-simulation/tmp/ppt_edit/中期报告.pptx");
const pres = await PresentationFile.importPptx(pptx);
console.log('slides', pres.slides.count);
for (let i=0;i<pres.slides.count;i++) {
  const slide = pres.slides.getItem(i);
  console.log('slide', i+1, Object.keys(slide));
  console.log('shapes?', slide.shapes?.count, 'images?', slide.images?.count, 'charts?', slide.charts?.count, 'tables?', slide.tables?.count);
  const texts=[];
  if (slide.shapes?.items) {
    for (const shape of slide.shapes.items.slice(0,20)) {
      let text='';
      try { text = String(shape.text ?? shape.text?.toString?.() ?? ''); } catch {}
      texts.push({geom: shape.geometry, pos: shape.position, text});
    }
  }
  console.log(JSON.stringify(texts.slice(0,8), null, 2));
}
