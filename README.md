# hermes-skill-https-clock-sync

> HTTPS-based clock sync for Linux hosts when NTP/UDP-123 is firewalled.
> Hermes skill — install with `hermes skills install`.

## What it solves

System clock drifts visibly (seconds to minutes per day), `timedatectl` reports
unsynchronized, `chrony` / `ntpdate` / `sntp` aren't installed, and the network
only allows a small whitelist of HTTPS endpoints (e.g. corporate firewalls, RK35xx /
Armbian boards behind carrier NAT).

This skill reads the `Date:` HTTP header from a stable CDN (Baidu / NTSc /
Cloudflare) via `curl`, and writes the result back via `date -u -s` +
`hwclock -w`. A systemd timer fires it every 48 hours; precision stays within
±1 second long-term.

## Install (on the host that needs clock sync)

```bash
# 1. Verify environment
bash scripts/preflight-check.sh

# 2. Drop the sync script
sudo cp scripts/setclock-http.sh /usr/local/bin/setclock-http
sudo chmod +x /usr/local/bin/setclock-http

# 3. Drop the systemd units
sudo cp templates/setclock-http.service /etc/systemd/system/
sudo cp templates/setclock-http.timer    /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now setclock-http.timer
```

## Install (as a Hermes skill)

```bash
hermes skills install breezi30/hermes-skill-https-clock-sync
```

## Documentation

Full documentation lives in **[SKILL.md](SKILL.md)** — read that for the
trigger conditions, runbook, ops/troubleshooting tables, and pitfalls.

## Files

| Path | Purpose |
|---|---|
| `SKILL.md` | Main skill documentation (trigger, deploy, ops, pitfalls) |
| `scripts/setclock-http.sh` | The sync script (deploy to `/usr/local/bin/`) |
| `scripts/preflight-check.sh` | Pre-deploy environment probe |
| `templates/setclock-http.service` | systemd service unit (oneshot) |
| `templates/setclock-http.timer` | systemd timer unit (48h + on-boot) |
| `references/hermes-skills-publish-mechanics.md` | Notes on publishing skills to the Hermes Skills Hub |

## When NOT to use

If NTP works on the host, use `systemd-timesyncd` or `chrony` directly —
they're more accurate and need zero maintenance.

## Tested on

RK3528 Pro / Armbian Ubuntu 24.04 / aarch64 — 2026-06-15.

## License

MIT — see [LICENSE](LICENSE).

## Release process

Releases are **fully automated via GitHub Actions** — no manual clicks.

1. Bump version in `SKILL.md` description (if needed)
2. Commit your changes to a feature branch and open a PR → CI runs `validate`
3. After PR merges to `main`, create a tag:
   ```bash
   git tag -a v1.1.0 -m "v1.1.0: <one-line summary>"
   git push origin v1.1.0
   ```
4. The `release` workflow:
   - Reads `RELEASE_NOTES_v1.1.0.md` from the repo (if present)
   - Falls back to `git log` since the previous tag (if no notes file)
   - Creates a GitHub Release at `releases/tag/v1.1.0`

**Tags with `-` are marked as prerelease** (e.g. `v1.1.0-rc1`).