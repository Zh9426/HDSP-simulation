import { FileBlob, PresentationFile } from "@oai/artifact-tool";
const pptx = await FileBlob.load("F:/GitHub/HDSP-simulation/tmp/ppt_edit/中期报告.pptx");
const pres = await PresentationFile.importPptx(pptx);
const slide = pres.slides.getItem(8);
console.log('image count', slide.images.items.length);
console.log('can delete on shapes?', typeof slide.shapes.items[0].delete);
