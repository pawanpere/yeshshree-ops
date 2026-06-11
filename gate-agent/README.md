# gate-agent (P19 — not yet built)
Windows folder-watcher for the gate ScanJet. Uploads scans to POST /gate-entries/scans,
sends POST /system/agent-heartbeat every 60s. File deleted from queue only after 200 ack.
See Architecture §5.7 and §11.4.
