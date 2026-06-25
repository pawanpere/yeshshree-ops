"""Generate printable DUMMY tax-invoice PDFs (one per dummy PO) for the live demo.
Print these, then scan them — the prominent P.O. No. is what the OCR matches on.
Run:  python3 make_invoice.py     ->  writes demo/dummy_invoices/<po>.pdf"""
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (SimpleDocTemplate, Table, TableStyle, Paragraph,
                                Spacer)

import dummy_po

OUT = os.path.join(os.path.dirname(__file__), "dummy_invoices")
os.makedirs(OUT, exist_ok=True)

BUYER = ("Yeshshree Press Comps Pvt. Ltd. (Plant 1117)",
         "B-4, MIDC Waluj, Chh. Sambhajinagar, Maharashtra 431136",
         "27AAACY0908Q1ZW")
NAVY = colors.HexColor("#1F4E78")

_ONES = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
         "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen",
         "Seventeen", "Eighteen", "Nineteen"]
_TENS = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]


def _two(n):
    return _ONES[n] if n < 20 else _TENS[n // 10] + (" " + _ONES[n % 10] if n % 10 else "")


def in_words(n: int) -> str:
    if n == 0:
        return "Zero"
    parts, units = [], [(10000000, "Crore"), (100000, "Lakh"), (1000, "Thousand"), (100, "Hundred")]
    for div, name in units:
        if n >= div:
            parts.append(_two(n // div) + " " + name)
            n %= div
    if n:
        parts.append(_two(n))
    return " ".join(parts)


def generate(po_no: str) -> str:
    po = dummy_po.DUMMY_POS[po_no]
    inv = po["invoice"]
    qty, rate = float(inv["qty"]), float(po["rate"])
    taxable = round(qty * rate, 2)
    cgst = sgst = round(taxable * 0.09, 2)
    total = round(taxable + cgst + sgst, 2)

    styles = getSampleStyleSheet()
    small = ParagraphStyle("s", parent=styles["Normal"], fontSize=8.5, leading=11)
    h = ParagraphStyle("h", parent=styles["Normal"], fontSize=8.5, leading=11, textColor=colors.grey)
    path = os.path.join(OUT, f"{po_no}.pdf")
    doc = SimpleDocTemplate(path, pagesize=A4, topMargin=14 * mm, bottomMargin=14 * mm,
                            leftMargin=14 * mm, rightMargin=14 * mm)
    el = []

    # header band
    hdr = Table([[Paragraph(f"<b><font size=15 color='#1F4E78'>{po['vendor_name']}</font></b><br/>"
                            f"<font size=8>{po['vendor_addr']}</font><br/>"
                            f"<font size=8>GSTIN: {po['vendor_gstin']}</font>", small),
                 Paragraph("<b><font size=14>TAX INVOICE</font></b><br/>"
                           "<font size=7 color='#B00000'>SAMPLE — DEMO DOCUMENT</font>", small)]],
                colWidths=[120 * mm, 62 * mm])
    hdr.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"),
                             ("ALIGN", (1, 0), (1, 0), "RIGHT"),
                             ("LINEBELOW", (0, 0), (-1, -1), 1.2, NAVY),
                             ("BOTTOMPADDING", (0, 0), (-1, -1), 8)]))
    el += [hdr, Spacer(1, 8)]

    # meta: bill-to + invoice details (PO No prominent)
    bill = Paragraph(f"<b>Bill To / Ship To</b><br/>{BUYER[0]}<br/>{BUYER[1]}<br/>"
                     f"GSTIN: {BUYER[2]}", small)
    meta = Paragraph(
        f"Invoice No: <b>{inv['no']}</b><br/>Invoice Date: <b>{inv['date']}</b><br/>"
        f"<font size=11 color='#1F4E78'><b>P.O. No.: {po['po_no']}</b></font><br/>"
        f"Vehicle No: {inv['vehicle']}<br/>E-Way Bill: {inv['eway']}<br/>"
        f"Transporter: {inv['transporter']}", small)
    mt = Table([[bill, meta]], colWidths=[100 * mm, 82 * mm])
    mt.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"),
                            ("BOX", (0, 0), (-1, -1), 0.5, colors.grey),
                            ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.grey),
                            ("LEFTPADDING", (0, 0), (-1, -1), 6), ("TOPPADDING", (0, 0), (-1, -1), 6),
                            ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]))
    el += [mt, Spacer(1, 10)]

    # line items
    rows = [["Sr", "Description of Goods", "HSN", "Qty", "UOM", "Rate", "Amount"],
            ["1", f"{po['material_desc']}\nMaterial code: {po['material_code']} · "
                  f"Batch/Heat: {inv['batch']}", inv["hsn"], f"{qty:.3f}", po["uom"],
             f"{rate:,.2f}", f"{taxable:,.2f}"]]
    lt = Table(rows, colWidths=[10 * mm, 78 * mm, 20 * mm, 18 * mm, 12 * mm, 22 * mm, 22 * mm])
    lt.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), NAVY), ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTSIZE", (0, 0), (-1, -1), 8.5), ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey), ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ALIGN", (3, 0), (-1, -1), "RIGHT"), ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    el += [lt]

    # totals
    tot = Table([["Taxable Value", f"{taxable:,.2f}"], ["CGST @ 9%", f"{cgst:,.2f}"],
                 ["SGST @ 9%", f"{sgst:,.2f}"], ["Total (Incl. GST)", f"{total:,.2f}"]],
                colWidths=[40 * mm, 32 * mm], hAlign="RIGHT")
    tot.setStyle(TableStyle([("FONTSIZE", (0, 0), (-1, -1), 9), ("ALIGN", (1, 0), (1, -1), "RIGHT"),
                             ("LINEABOVE", (0, 0), (-1, 0), 0.5, colors.grey),
                             ("FONTNAME", (0, -1), (-1, -1), "Helvetica-Bold"),
                             ("LINEABOVE", (0, -1), (-1, -1), 0.8, NAVY),
                             ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]))
    el += [Spacer(1, 6), tot, Spacer(1, 8),
           Paragraph(f"<b>Amount in words:</b> Rupees {in_words(int(round(total)))} Only", small),
           Spacer(1, 18),
           Paragraph(f"For <b>{po['vendor_name']}</b><br/><br/><br/>Authorised Signatory", h),
           Spacer(1, 6),
           Paragraph("This is a computer-generated sample invoice for demonstration only.", h)]
    doc.build(el)
    return path


if __name__ == "__main__":
    for po_no in dummy_po.DUMMY_POS:
        print("wrote", generate(po_no))
