"""OCR + field extraction for the live demo.

PDF/image -> Google Cloud Vision DOCUMENT_TEXT_DETECTION -> text -> extract the
fields we match on (PO number is the KEY; GSTIN / invoice no / value are extras).
Vision key is read from the GVISION_KEY env var (never hardcode it)."""
import io
import os
import re
import json
import ssl
import base64
import urllib.request

import certifi
import pypdfium2 as pdfium
from PIL import Image

_SSL = ssl.create_default_context(cafile=certifi.where())
GSTIN_RE = re.compile(r"\b\d{2}[A-Z]{5}\d{4}[A-Z][A-Z0-9]Z[A-Z0-9]\b")


def render_to_jpeg_bytes(content: bytes, scale: int = 3) -> bytes:
    """First page of a PDF (or any image) bytes -> JPEG bytes for Vision + the UI."""
    if content[:5] == b"%PDF-":
        pdf = pdfium.PdfDocument(content)
        try:
            img = pdf[0].render(scale=scale).to_pil().convert("RGB")
        finally:
            pdf.close()
    else:
        img = Image.open(io.BytesIO(content)).convert("RGB")
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=88)
    return buf.getvalue()


def render_to_jpeg(path: str, scale: int = 3) -> bytes:
    """Convenience: read a file path and render its first page to JPEG."""
    with open(path, "rb") as f:
        return render_to_jpeg_bytes(f.read(), scale)


def vision_ocr(jpeg_bytes: bytes, key: str | None = None, timeout: int = 60) -> str:
    """Return the full OCR text for a JPEG. Raises with a clear message on failure.
    `timeout` (seconds) bounds the Vision HTTP call so a bad connection fails fast."""
    key = key or os.environ.get("GVISION_KEY")
    if not key:
        raise RuntimeError("GVISION_KEY not set — export your Google Vision API key")
    req = {"requests": [{"image": {"content": base64.b64encode(jpeg_bytes).decode()},
                         "features": [{"type": "DOCUMENT_TEXT_DETECTION"}]}]}
    r = urllib.request.Request(
        f"https://vision.googleapis.com/v1/images:annotate?key={key}",
        data=json.dumps(req).encode(), headers={"Content-Type": "application/json"})
    resp = json.loads(urllib.request.urlopen(r, timeout=timeout, context=_SSL).read())
    res = resp["responses"][0]
    if "error" in res:
        raise RuntimeError(f"Vision API error: {res['error'].get('message')}")
    return res.get("fullTextAnnotation", {}).get("text", "")


def extract_fields(text: str) -> dict:
    """Pull the fields we care about. PO candidates are any 9–10 digit tokens
    (the caller fuzzy-matches them to the known PO list, so a single OCR digit
    slip still resolves)."""
    flat = text.replace(",", " ")
    po_candidates = re.findall(r"\b(5[0-9]{8,9})\b", flat)      # SAP PO numbers ~ 5200xxxxxx
    # also catch "PO: 520000845" / "PO No 520000845"
    for m in re.finditer(r"PO[\s:.No]*?(\d{6,12})", text, re.I):
        po_candidates.append(m.group(1))
    gstins = GSTIN_RE.findall(text)
    inv = None
    m = re.search(r"(?:Invoice\s*No\.?|GST\s*Invoice\s*No\.?)\s*[:.]?\s*([A-Z0-9]{6,18})", text, re.I)
    if m:
        inv = m.group(1)
    return {
        "po_candidates": list(dict.fromkeys(po_candidates)),   # dedupe, keep order
        "vendor_gstin": gstins[0] if gstins else None,
        "invoice_no": inv,
        "raw_text": text,
    }
