"""Application settings. Every variable is documented in .env.example (repo root)."""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./dev.db"  # overridden by DATABASE_URL everywhere real
    jwt_secret: str = "dev-secret-not-for-production-0000000000"
    jwt_access_minutes: int = 15
    jwt_refresh_days: int = 30

    s3_endpoint: str = ""
    s3_access_key: str = ""
    s3_secret_key: str = ""
    s3_bucket: str = "yeshshree-files"

    ops_mode: str = "parallel_run"  # parallel_run | authoritative (mirrored in app_settings)

    # The plant's local timezone. Instants are stored in UTC (timestamptz), but a
    # *shift/plan date* is a local calendar date — deriving it from UTC midnight files
    # 00:00–05:30 IST production under the wrong day. Single-plant today (1117 = IST).
    plant_tz: str = "Asia/Kolkata"

    # CORS — only the Flutter WEB build needs this (a real Android build uses native
    # HTTP, so CORS never applies on device). cors_origins = explicit production
    # origins (comma-separated); cors_allow_localhost reflects any
    # http(s)://localhost:<port> so dev/preview web builds reach the API.
    cors_origins: str = ""
    cors_allow_localhost: bool = True

    app_min_version: str = "0.1.0"
    app_latest_version: str = "0.1.0"
    apk_url: str = ""

    sap_sftp_host: str = ""
    sap_sftp_user: str = ""
    sap_sftp_key_path: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()
