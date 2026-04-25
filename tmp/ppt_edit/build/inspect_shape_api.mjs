import { FileBlob, PresentationFile } from "@oai/artifact-tool";
const pptx = await FileBlob.load("F:/GitHub/HDSP-simulation/tmp/ppt_edit/中期报告.pptx");
const pres = await PresentationFile.importPptx(pptx);
const slide = pres.slides.getItem(7);
const shape = slide.shapes.items[1];
console.log('shape keys', Object.keys(shape));
console.log('has delete', typeof shape.delete);
console.log('text before', String(shape.text));
