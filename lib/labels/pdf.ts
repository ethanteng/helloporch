import { PDFDocument, PrintScaling, StandardFonts, rgb, type PDFImage } from "pdf-lib";
import { canvasContext, loadPhoto, paintCard, PRINT_NOTE, sheetDescription, type Contact } from "./artwork";
import { cornerMarks, LETTER_HEIGHT, LETTER_WIDTH, makeSheets, SCALE_MARKS, SHEET_MARGIN, type Dimensions, type Line } from "./layout";

export async function createLabelPdf(contacts: Contact[], dimensions: Dimensions, setCount: number): Promise<Blob> {
  const pdf = await PDFDocument.create();
  pdf.setTitle("Porch phone labels");
  pdf.catalog.getOrCreateViewerPreferences().setPrintScaling(PrintScaling.None);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const pages = makeSheets(dimensions, contacts.length, setCount);
  const { width, height } = pages[0][0];
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(width * 300 / 72);
  canvas.height = Math.round(height * 300 / 72);
  const context = canvasContext(canvas);
  const art: PDFImage[] = [];
  for (const contact of contacts) {
    const photo = contact.photo ? await loadPhoto(contact.photo) : null;
    context.setTransform(canvas.width / width, 0, 0, canvas.height / height, 0, 0);
    paintCard(context, contact, width, height, photo);
    art.push(photo ? await pdf.embedJpg(canvas.toDataURL("image/jpeg", 0.96)) : await pdf.embedPng(canvas.toDataURL("image/png")));
  }
  pages.forEach((cards, index) => {
    const page = pdf.addPage([LETTER_WIDTH, LETTER_HEIGHT]);
    const ink = rgb(0.13, 0.1, 0.07);
    const line = ([x1, y1, x2, y2]: Line, thickness: number) => page.drawLine({
      start: { x: x1, y: LETTER_HEIGHT - y1 }, end: { x: x2, y: LETTER_HEIGHT - y2 },
      thickness, color: rgb(0.37, 0.34, 0.31),
    });
    page.drawText("Porch phone labels", { x: SHEET_MARGIN, y: LETTER_HEIGHT - 42, size: 16, font: bold, color: ink });
    page.drawText(sheetDescription(dimensions, index, pages.length), { x: SHEET_MARGIN, y: LETTER_HEIGHT - 59, size: 10, font: regular, color: ink });
    page.drawText(PRINT_NOTE, { x: SHEET_MARGIN, y: LETTER_HEIGHT - 74, size: 10, font: regular, color: ink });
    for (const card of cards) {
      page.drawImage(art[card.contactIndex], { x: card.x, y: LETTER_HEIGHT - card.y - card.height, width: card.width, height: card.height });
      cornerMarks(card).forEach((mark) => line(mark, 0.45));
    }
    SCALE_MARKS.forEach((mark) => line(mark, 0.65));
    page.drawText("1-inch scale check", { x: SHEET_MARGIN + 82, y: LETTER_HEIGHT - 751, size: 9, font: regular, color: ink });
  });
  return new Blob([new Uint8Array(await pdf.save())], { type: "application/pdf" });
}
