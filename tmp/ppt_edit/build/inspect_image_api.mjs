import { FileBlob, PresentationFile } from "@oai/artifact-tool";
const pptx = await FileBlob.load("F:/GitHub/HDSP-simulation/tmp/ppt_edit/中期报告.pptx");
const pres = await PresentationFile.importPptx(pptx);
const slide = pres.slides.getItem(8);
const img = slide.images.items[0];
console.log('keys', Object.keys(img));
console.log('proto', Object.getOwnPropertyNames(Object.getPrototypeOf(img)));
console.log('type', img.type);
console.log('position', img.position);
