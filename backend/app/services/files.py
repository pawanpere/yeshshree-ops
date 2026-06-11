"""File storage (P15). Driver chosen by config: S3-compatible (R2/MinIO) when
S3_ENDPOINT is set, local-disk otherwise (sandbox/dev). Photos are NON-BLOCKING by
design (§11.15): entries post without them; uploads attach later and clear the flag."""
import hashlib
from pathlib import Path

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.gate import File as FileRow

_LOCAL_DIR = Path("filestore")


def save_file(db: Session, *, content: bytes, filename: str, kind: str,
              mime: str | None, uploaded_by: int | None) -> FileRow:
    """Store bytes + create the files row in the CURRENT transaction (caller commits)."""
    sha = hashlib.sha256(content).hexdigest()
    key = f"{kind}/{sha[:2]}/{sha}-{filename}"
    s = get_settings()
    if s.s3_endpoint:
        import boto3  # lazy: not a sandbox dependency
        client = boto3.client("s3", endpoint_url=s.s3_endpoint,
                              aws_access_key_id=s.s3_access_key,
                              aws_secret_access_key=s.s3_secret_key)
        client.put_object(Bucket=s.s3_bucket, Key=key, Body=content,
                          ContentType=mime or "application/octet-stream")
    else:
        path = _LOCAL_DIR / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    row = FileRow(storage_key=key, kind=kind, mime=mime, size_bytes=len(content),
                  sha256=sha, uploaded_by=uploaded_by)
    db.add(row)
    db.flush()
    return row


def load_file(storage_key: str) -> bytes:
    s = get_settings()
    if s.s3_endpoint:
        import boto3
        client = boto3.client("s3", endpoint_url=s.s3_endpoint,
                              aws_access_key_id=s.s3_access_key,
                              aws_secret_access_key=s.s3_secret_key)
        return client.get_object(Bucket=s.s3_bucket, Key=storage_key)["Body"].read()
    return (_LOCAL_DIR / storage_key).read_bytes()


def find_duplicate_scan(db: Session, content: bytes) -> FileRow | None:
    """Same bytes scanned twice (guard re-scans 'because nothing happened',
    Failure Scenarios #3) → return the existing file instead of a new pipeline run."""
    sha = hashlib.sha256(content).hexdigest()
    return db.query(FileRow).filter_by(sha256=sha, kind="scan").one_or_none()
