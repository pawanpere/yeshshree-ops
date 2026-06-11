"""Scan decode (P17). Spec: Architecture §5.7. PURE logic — no DB, no HTTP.

Pipeline: bytes (PDF or image) → raster → zxing-cpp → parse what we recognise:
- GST e-invoice QR: a JWS ('eyJ…'); the middle segment is base64url JSON whose
  "data" field is a STRINGIFIED JSON with SellerGstin/DocNo/DocDt/TotInvVal/Irn/….
- TATA-style PDF417: CSV-ish line with PO no, invoice no/date, GSTIN, values,
  vehicle reg, weights. Best-effort regex parse.
- Anything else: kept raw (decode_status='partial' if that's all we got).

Golden-tested against the 3 real scanned invoices in data/ (tests/test_scans.py).
zxingcpp / pypdfium2 / PIL are imported lazily so the API process can boot without
them (decode endpoints are the only consumers)."""
import base64
import io
import json
import re
from dataclasses import dataclass, field
from datetime import datetime

PO_NO_RE = re.compile(r"PO:\s*(\d+)")
VEHICLE_RE = re.compile(r"\b[A-Z]{2}\s?\d{2}\s?[A-Z]{1,3}\s?\d{4}\b")
GSTIN_RE = re.compile(r"\b\d{2}[A-Z]{5}\d{4}[A-Z][A-Z0-9]Z[A-Z0-9]\b")
# the JWS body keys we surface from an e-invoice QR
_EINVOICE_KEYS = ("SellerGstin", "DocNo", "DocDt", "TotInvVal", "Irn",
                  "MainHsnCode", "ItemCnt")


@dataclass
class DecodeResult:
    decode_status: str                       # 'decoded' | 'partial' | 'none'
    qr_payload: dict | None = None           # parsed e-invoice fields (DocDt → ISO)
    pdf417_payload: str | None = None        # raw PDF417 text, archived verbatim
    raw_barcodes: list = field(default_factory=list)   # [{'format','text'}] everything seen
    suggestions: dict = field(default_factory=dict)    # gate-screen prefill


def _b64url_json(segment: str) -> dict:
    pad = "=" * (-len(segment) % 4)
    return json.loads(base64.urlsafe_b64decode(segment + pad))


def _iso_date(raw: str | None) -> str | None:
    """e-invoice DocDt is dd/mm/yyyy; PDF417 uses dd.mm.yyyy. → ISO yyyy-mm-dd."""
    if not raw:
        return None
    for fmt in ("%d/%m/%Y", "%d.%m.%Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(raw.strip(), fmt).date().isoformat()
        except ValueError:
            continue
    return None


def parse_einvoice_qr(text: str) -> dict | None:
    """GST e-invoice signed QR (JWS). Returns the fields we care about or None.
    Signature is NOT verified — we use the QR as data entry, not as legal proof."""
    parts = text.split(".")
    if len(parts) != 3 or not text.startswith("eyJ"):
        return None
    try:
        body = _b64url_json(parts[1])
        data = body["data"]
        if isinstance(data, str):
            data = json.loads(data)
    except (ValueError, KeyError, TypeError):
        return None
    out = {k: data.get(k) for k in _EINVOICE_KEYS}
    out["DocDt"] = _iso_date(out.get("DocDt"))
    return out if out.get("SellerGstin") or out.get("Irn") else None


def parse_pdf417(text: str) -> dict | None:
    """TATA dispatch PDF417, observed shape (golden scan doc008572…):
    ',PO:520000845  VC: 10,3131079408,24.05.2026,27AAACT2803M1ZB,369366.15,
     313022.15,MH12MV9997,28172.00,0.00,28172.00'
    Comma-separated; vendor-specific, so everything is best-effort."""
    out: dict = {}
    m = PO_NO_RE.search(text)
    if m:
        out["po_no"] = m.group(1)
    m = VEHICLE_RE.search(text.replace(" ", " "))
    if m:
        out["vehicle_no"] = m.group(0).replace(" ", "")
    m = GSTIN_RE.search(text)
    if m:
        out["gstin"] = m.group(0)
    tokens = [t.strip() for t in text.split(",")]
    # invoice no = first all-digit token of plausible length that is not the PO no
    for t in tokens:
        if t.isdigit() and 6 <= len(t) <= 16 and t != out.get("po_no"):
            out["invoice_no"] = t
            break
    for t in tokens:
        d = _iso_date(t)
        if d:
            out["invoice_date"] = d
            break
    # invoice value = first decimal token right after the GSTIN, if present
    if "gstin" in out:
        try:
            gi = tokens.index(out["gstin"])
            if gi + 1 < len(tokens):
                out["invoice_value"] = float(tokens[gi + 1])
        except (ValueError, IndexError):
            pass
    # gross weight = first decimal token right after the vehicle reg
    if "vehicle_no" in out:
        for i, t in enumerate(tokens):
            if t.replace(" ", "") == out["vehicle_no"] and i + 1 < len(tokens):
                try:
                    out["weight"] = float(tokens[i + 1])
                except ValueError:
                    pass
                break
    return out or None


def _render_to_image(content: bytes, mime_hint: str | None):
    """PDF → render page 1 at scale 4 (≈300 dpi, enough for PDF417 quiet zones);
    anything else → PIL open."""
    is_pdf = content[:5] == b"%PDF-" or (mime_hint or "").lower().endswith("pdf")
    if is_pdf:
        import pypdfium2 as pdfium
        pdf = pdfium.PdfDocument(content)
        try:
            return pdf[0].render(scale=4).to_pil()
        finally:
            pdf.close()
    from PIL import Image
    return Image.open(io.BytesIO(content))


def build_suggestions(qr: dict | None, p417: dict | None) -> dict:
    """Gate-screen prefill. QR (signed by NIC) wins over PDF417 where both exist."""
    s: dict = {}
    if p417:
        s.update({k: p417.get(k) for k in
                  ("po_no", "vehicle_no", "weight") if p417.get(k) is not None})
        for src, dst in (("gstin", "vendor_gstin"), ("invoice_no", "invoice_no"),
                         ("invoice_date", "invoice_date"), ("invoice_value", "invoice_value")):
            if p417.get(src) is not None:
                s[dst] = p417[src]
    if qr:
        for src, dst in (("SellerGstin", "vendor_gstin"), ("DocNo", "invoice_no"),
                         ("DocDt", "invoice_date"), ("TotInvVal", "invoice_value"),
                         ("Irn", "irn"), ("MainHsnCode", "hsn")):
            if qr.get(src) is not None:
                s[dst] = qr[src]
    return s


def decode_document(content: bytes, mime_hint: str | None = None) -> DecodeResult:
    """bytes in (PDF page or photo) → DecodeResult. Never raises on undecodable
    content — a scan with no barcodes is a normal outcome (decode_status='none',
    manual entry, image still archived per §5.7)."""
    import zxingcpp
    try:
        image = _render_to_image(content, mime_hint)
    except Exception:
        return DecodeResult(decode_status="none")
    barcodes = zxingcpp.read_barcodes(image)
    qr_payload: dict | None = None
    pdf417_payload: str | None = None
    raw = []
    for b in barcodes:
        # zxingcpp prints 'QR Code' / 'Code 128' / 'PDF417' — normalise the spaces
        fmt = str(b.format).removeprefix("BarcodeFormat.").replace(" ", "")
        raw.append({"format": fmt, "text": b.text})
        if qr_payload is None and fmt == "QRCode":
            qr_payload = parse_einvoice_qr(b.text)
        elif pdf417_payload is None and fmt == "PDF417":
            pdf417_payload = b.text
    p417 = parse_pdf417(pdf417_payload) if pdf417_payload else None
    if qr_payload or p417:
        status = "decoded"
    elif raw:
        status = "partial"
    else:
        status = "none"
    return DecodeResult(decode_status=status, qr_payload=qr_payload,
                        pdf417_payload=pdf417_payload, raw_barcodes=raw,
                        suggestions=build_suggestions(qr_payload, p417))
