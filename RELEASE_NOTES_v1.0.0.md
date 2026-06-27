# v1.0.0 — 2026-06-27

Initial public release of **HTTPS-based clock sync for NTP-blocked Linux hosts**.

## What's included

- `setclock-http.sh` — parses the `Date:` HTTP header from a stable CDN (Baidu / NTSc / Cloudflare) and writes the result back via `date -u -s` + `hwclock -w`.
- Systemd units: 48h cycle + on-boot 30s recovery timer.
- `preflight-check.sh` — one-shot environment probe (NTP dead? HTTPS reachable? drift amount?).
- Full SKILL.md with trigger conditions, deploy runbook, ops/troubleshooting tables, and pitfalls.
- Offset threshold (3600s) protects against upstream-poisoned time.

## Tested on

RK3528 Pro / Armbian Ubuntu 24.04 / aarch64 — 2026-06-15.

## Expected precision

±1 second long-term (driven by 48h cycle + ~100ms HTTPS RTT). Adequate for logs, cron, TLS handshake freshness. Not NTP-quality.

## Install

```bash
# As a Hermes skill
hermes skills install breezi30/hermes-skill-https-clock-sync/SKILL.md

# Or manually
git clone https://github.com/breezi30/hermes-skill-https-clock-sync.git
cd hermes-skill-https-clock-sync
bash scripts/preflight-check.sh
sudo cp scripts/setclock-http.sh /usr/local/bin/setclock-http
sudo chmod +x /usr/local/bin/setclock-http
sudo cp templates/setclock-http.service /etc/systemd/system/
sudo cp templates/setclock-http.timer    /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now setclock-http.timer
```

## License

MIT