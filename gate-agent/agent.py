"""gate-agent (P19) — ScanJet folder watcher. Spec: Architecture §5.7 + §11.4.

Stdlib only (urllib/configparser/logging) so it packages to a single Windows .exe
(pyinstaller) with zero dependencies. Behaviour contract:
- A scan file is moved to <watch_dir>/uploaded/ ONLY after the API answered 200.
  On any failure it stays put and is retried forever with backoff — a dead network
  never loses a scan (the server dedupes identical bytes, so re-posts are safe).
- Heartbeat POST /system/agent-heartbeat every heartbeat_seconds (§11.4).

Run:  python agent.py [path\\to\\agent.ini]     (default: agent.ini next to this file)
"""
import configparser
import json
import logging
import shutil
import sys
import time
import uuid
import urllib.error
import urllib.request
from pathlib import Path

EXTENSIONS = {".pdf", ".jpg", ".jpeg", ".png"}
MAX_BACKOFF = 300  # seconds


def load_config(path: Path) -> dict:
    cp = configparser.ConfigParser()
    if not cp.read(path):
        sys.exit(f"config not found: {path} (copy agent.ini.example to agent.ini)")
    a = cp["agent"]
    return {
        "api_url": a["api_url"].rstrip("/"),
        "token": a["token"],
        "device_key": a["device_key"],
        "watch_dir": Path(a["watch_dir"]),
        "poll_seconds": a.getfloat("poll_seconds", 2.0),
        "heartbeat_seconds": a.getfloat("heartbeat_seconds", 60.0),
    }


def post(url: str, token: str, data: bytes, content_type: str) -> dict:
    req = urllib.request.Request(url, data=data, method="POST", headers={
        "Authorization": f"Bearer {token}", "Content-Type": content_type})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))


def post_scan(cfg: dict, path: Path) -> dict:
    """Multipart by hand — stdlib has no multipart encoder."""
    boundary = uuid.uuid4().hex
    mime = "application/pdf" if path.suffix.lower() == ".pdf" else "image/" + (
        "png" if path.suffix.lower() == ".png" else "jpeg")
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
            f"filename=\"{path.name}\"\r\nContent-Type: {mime}\r\n\r\n").encode()
    body += path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    return post(f"{cfg['api_url']}/api/v1/gate-entries/scans", cfg["token"], body,
                f"multipart/form-data; boundary={boundary}")


def send_heartbeat(cfg: dict, last_scan_at: str | None) -> None:
    payload = json.dumps({"device_key": cfg["device_key"], "agent_version": "1.0.0",
                          "watch_folder_ok": cfg["watch_dir"].is_dir(),
                          "last_scan_at": last_scan_at}).encode()
    post(f"{cfg['api_url']}/api/v1/system/agent-heartbeat", cfg["token"], payload,
         "application/json")


def stable_files(watch_dir: Path, poll_seconds: float) -> list[Path]:
    """New files whose size stopped changing — the ScanJet may still be writing."""
    candidates = [p for p in watch_dir.iterdir()
                  if p.is_file() and p.suffix.lower() in EXTENSIONS]
    sizes = {p: p.stat().st_size for p in candidates}
    time.sleep(min(1.0, poll_seconds / 2))
    return [p for p in candidates
            if p.exists() and p.stat().st_size == sizes[p] and sizes[p] > 0]


def main() -> None:
    cfg = load_config(Path(sys.argv[1]) if len(sys.argv) > 1
                      else Path(__file__).with_name("agent.ini"))
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s",
        handlers=[logging.FileHandler(Path(__file__).with_name("agent.log")),
                  logging.StreamHandler()])
    log = logging.getLogger("gate-agent")
    uploaded_dir = cfg["watch_dir"] / "uploaded"
    uploaded_dir.mkdir(parents=True, exist_ok=True)
    log.info("watching %s -> %s", cfg["watch_dir"], cfg["api_url"])
    last_heartbeat = 0.0
    last_scan_at: str | None = None
    failures = 0
    while True:
        try:
            if time.time() - last_heartbeat >= cfg["heartbeat_seconds"]:
                try:
                    send_heartbeat(cfg, last_scan_at)
                    last_heartbeat = time.time()
                except Exception as exc:  # heartbeat failure never blocks uploads
                    log.warning("heartbeat failed: %s", exc)
                    last_heartbeat = time.time()  # don't hammer; retry next interval
            for path in stable_files(cfg["watch_dir"], cfg["poll_seconds"]):
                try:
                    result = post_scan(cfg, path)
                    dest = uploaded_dir / path.name
                    if dest.exists():  # same name re-scanned later
                        dest = uploaded_dir / f"{path.stem}-{int(time.time())}{path.suffix}"
                    shutil.move(str(path), str(dest))  # ONLY after 200
                    last_scan_at = time.strftime("%Y-%m-%dT%H:%M:%S")
                    failures = 0
                    log.info("uploaded %s -> scan id=%s decode=%s duplicate=%s",
                             path.name, result.get("scan", {}).get("id"),
                             result.get("scan", {}).get("decode_status"),
                             result.get("duplicate"))
                except urllib.error.HTTPError as exc:
                    failures += 1
                    log.error("upload %s rejected: HTTP %s %s", path.name, exc.code,
                              exc.read()[:300])
                except Exception as exc:  # network down etc. — file stays, retry
                    failures += 1
                    log.error("upload %s failed (attempt kept on disk): %s",
                              path.name, exc)
            sleep = cfg["poll_seconds"] * (2 ** min(failures, 8))
            time.sleep(min(sleep, MAX_BACKOFF))
        except KeyboardInterrupt:
            log.info("stopping")
            return
        except Exception as exc:  # belt & braces: the loop itself never dies
            log.error("watch loop error: %s", exc)
            time.sleep(cfg["poll_seconds"])


if __name__ == "__main__":
    main()
