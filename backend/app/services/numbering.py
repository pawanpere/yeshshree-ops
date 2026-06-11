"""Document numbers (invariant 7): G-/GR-/ISS-/DN-/RGP- prefixes from doc_sequences,
allocated under row lock. Indian fiscal year (Apr–Mar) buckets the sequences."""
import datetime as dt

from sqlalchemy.orm import Session

from app.models.config_tables import DocSequence


def fiscal_year(today: dt.date | None = None) -> str:
    d = today or dt.date.today()
    start = d.year if d.month >= 4 else d.year - 1
    return f"{start}-{str(start + 1)[2:]}"


def next_doc_no(db: Session, doc_type: str, today: dt.date | None = None) -> str:
    """MUST be called inside the caller's transaction — the allocated number commits
    or rolls back together with the document that uses it."""
    fy = fiscal_year(today)
    row = (db.query(DocSequence)
           .filter_by(doc_type=doc_type, fiscal_year=fy)
           .with_for_update()  # no-op on SQLite (single writer); real lock on Postgres
           .one_or_none())
    if row is None:
        row = DocSequence(doc_type=doc_type, fiscal_year=fy, next_no=1)
        db.add(row)
        db.flush()
    n = row.next_no
    row.next_no = n + 1
    return f"{doc_type}-{n:05d}"
