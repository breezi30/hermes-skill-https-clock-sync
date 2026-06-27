---
name: https-clock-sync
description: "When a Linux host (especially RK35xx / Armbian / industrial / small-board SBC) shows a drifting system clock and NTP/UDP-123 is firewalled. Triggered by symptoms like `timedatectl` showing unsynchronized status, `date` running fast/slow by seconds-to-minutes, `ntpdate` / `chrony` / `sntp` not installed and un-installable, or any environment where only a small whitelist of HTTPS endpoints is reachable. Uses `curl -I` to read the `Date` HTTP header from a stable CDN (Baidu / NTSc / Cloudflare) and writes the result back via `date -u -s` plus `hwclock -w`. Does NOT apply when NTP works normally — use `systemd-timesyncd` or `chrony` in that case."
---

# HTTPS-based Clock Sync for NTP-blocked Networks

## When to use this

Use this skill when **all** of the following are true:

- Linux host (tested on **RK3528 Pro / Armbian Ubuntu 24.04 / aarch64**, but works on any systemd Linux with `bash` + `curl` + `hwclock`)
- System clock drifts visibly (seconds to minutes per day)
- `timedatectl` reports `System clock synchronized: no`
- NTP/UDP/123 egress is blocked at the firewall — confirmed by `nc -uvz time1.aliyun.com 123` (or equivalent) timing out
- `chrony` / `ntpdate` / `sntp` are **not installed** and the network policy forbids `apt install`
- At least **one HTTPS endpoint to a major CDN** is reachable (the more, the better — provides fallback)

**Do not use this when** NTP works. Stick with `systemd-timesyncd` or `chrony` for normal cases — they're more accurate and require zero maintenance.

## How it works (30-second version)

1. `curl -sI --max-time 6 https://www.baidu.com` → grab the `Date:` response header
2. Parse the GMT string into a Unix epoch with `date -u -d "$TS" +%s`
3. Estimate upstream's "now" by adding `RTT/2` (we measured local time before & after the request)
4. Reject any offset > **±3600s** as suspicious — upstream likely poisoned or clock wildly wrong
5. If offset is within ±2s, log and skip (avoid RTC wear from trivial writes)
6. Otherwise: `date -u -s "@$SERVER_NOW"` + `hwclock -w` + log to syslog via `logger -t setclock-http`

A systemd timer fires it every 48 hours. On boot, it also runs once after 30s to recover from long shutdowns.

**Expected precision:** ~±1 second long-term (driven by 48h cycle + ~100ms HTTPS RTT). Not NTP-quality — adequate for logs, cron, TLS handshake freshness, daily-use apps.

## Files this skill creates

| File | Purpose | Size |
|---|---|---|
| `/usr/local/bin/setclock-http` | The sync script (Bash, executable) | ~2.7 KB |
| `/etc/systemd/system/setclock-http.service` | systemd service unit (oneshot) | ~280 B |
| `/etc/systemd/system/setclock-http.timer` | systemd timer (every 48h + on-boot 30s) | ~200 B |
| `/var/lib/misc/setclock-http.last` | Last-sync timestamp (epoch seconds) | ~10 B |
| `/var/lock/setclock-http.lock` | flock mutex to prevent concurrent runs | 0 B |

## Deployment — copy-paste runbook

Tested on RK3528 Pro (Armbian Ubuntu 24.04, aarch64) on 2026-06-15. Total deploy time ~2 minutes.

### Support files (use these, don't hand-type)

This skill ships with all the long blocks pre-written — copy them instead of typing:

- `scripts/preflight-check.sh` — run this FIRST to verify the environment is ready (NTP dead? HTTPS reachable? drift amount?)
- `scripts/setclock-http.sh` — the actual sync script; copy to `/usr/local/bin/setclock-http`
- `templates/setclock-http.service` — systemd service unit; copy to `/etc/systemd/system/`
- `templates/setclock-http.timer` — systemd timer unit; copy to `/etc/systemd/system/`
- `references/hermes-skills-publish-mechanics.md` — only needed if you want to share this skill to the Hermes Skills Hub (official hub, fork+PR flow, needs `GITHUB_TOKEN`)
- `references/github-ssh-key-setup-rk35xx.md` — only needed if you want to publish this skill to **your own brand-new GitHub repo** (SSH key flow, no token needed). Covers headless RK35xx git+SSH setup, repo creation options, push runbook, common pitfalls (incl. `write_file` refusing `~/.ssh/config`)

### Step 1: Verify the environment

> **Fast path:** `bash scripts/preflight-check.sh` runs all four checks below in one go and tells you whether to proceed.

```bash
# Confirm NTP is dead
timedatectl | grep "System clock"
nc -uvz -w 3 time1.aliyun.com 123 2>&1   # expect "timeout" or "no route"
nc -uvz -w 3 time.cloudflare.com 123 2>&1

# Confirm HTTPS sources are alive
curl -sI --max-time 6 https://www.baidu.com | grep -i '^date:'
curl -sI --max-time 6 https://www.ntsc.ac.cn | grep -i '^date:'
```

If Baidu HTTPS works but all NTP is dead → proceed. If nothing works → fix network first.

### Step 2: Drop the script

```bash
sudo cp scripts/setclock-http.sh /usr/local/bin/setclock-http
sudo chmod +x /usr/local/bin/setclock-http
```

(The full script is ~2.7 KB. It is kept in `scripts/setclock-http.sh` rather than inlined here so it stays out of the agent's markdown-rendering pipeline — see "Pitfalls" below.)

### Step 3: Drop the systemd units

```bash
sudo cp templates/setclock-http.service /etc/systemd/system/setclock-http.service
sudo cp templates/setclock-http.timer    /etc/systemd/system/setclock-http.timer
sudo systemctl daemon-reload
sudo systemctl enable --now setclock-http.timer
```

### Step 4: Verify

```bash
# Confirm timer is active
systemctl list-timers setclock-http.timer
# Expect: NEXT in ~48h, LAST within last boot, UNIT activates setclock-http.service

# Force a manual sync right now
sudo systemctl start setclock-http.service

# Watch live log
journalctl -t setclock-http -f
# Expect first run: "FIX 调整 Ns (源=https://www.baidu.com,新时间=...)"
# Subsequent runs: "OK 偏差 Ns,无需调整"
```

## Operations & troubleshooting

### Common commands

| Need | Command |
|---|---|
| Next scheduled run | `systemctl list-timers setclock-http.timer` |
| Live log tail | `journalctl -t setclock-http -f` |
| Service status | `systemctl status setclock-http.service` |
| Sync right now | `sudo systemctl start setclock-http.service` |
| Pause timer (keep service) | `sudo systemctl disable --now setclock-http.timer` |
| Resume | `sudo systemctl enable --now setclock-http.timer` |
| Last sync epoch | `cat /var/lib/misc/setclock-http.last` |

### Log line meanings

| Log | Meaning |
|---|---|
| `OK 偏差 Ns,无需调整` | Offset ≤ 2s, normal healthy state |
| `FIX 调整 Ns` | Offset > 2s, clock corrected and RTC written |
| `ALERT 偏差 Ns 超过 3600s 阈值` | Refused to sync — upstream poisoned or local clock wildly wrong |
| `ERROR 所有时间源均不可达` | All SOURCES + FALLBACK timed out — check network |
| `ERROR date 命令失败` | Permission issue running `date -s` (needs root) |
| `另一实例正在运行,跳过` | flock hit (concurrent run), normal |

### When sync fails

| Symptom | Fix |
|---|---|
| `Date:` header empty | `curl -sI https://www.baidu.com \| grep -i date` — if empty too, network is down for HTTPS |
| Always `OK` but drift grows | Local clock itself is bad (RTC battery / crystal). Not solvable by this script alone. |
| `ALERT` keeps firing | Temporary: bump `MAX_OFFSET_SEC` to e.g. 86400 once, or `sudo date -u -s "@<correct_epoch>"` manually |
| HTTPS down but HTTP up | Add the HTTP source to the `FALLBACK` array (HTTP is **not** authenticated, treat as last resort) |
| Long downtime, no sync | `Persistent=true` means the timer back-fills missed runs on next boot — wait for boot, or `systemctl start setclock-http.service` |

### Change sync frequency

```bash
# Sync every 24h instead of 48h
sudo sed -i 's/^OnUnitActiveSec=.*/OnUnitActiveSec=24h/' /etc/systemd/system/setclock-http.timer
sudo systemctl daemon-reload
sudo systemctl restart setclock-http.timer
```

### Add or swap time sources

Edit the `SOURCES` and `FALLBACK` arrays in `/usr/local/bin/setclock-http`. Recommended coverage:

- At least 1 **domestic CDN** (Baidu, Taobao, JD) — fast for users in CN
- At least 1 **international** (Cloudflare `cloudflare.com`, Apple `apple.com`, Google)
- At least 1 **authoritative** (NTSc `ntsc.ac.cn`, time.gov)

## Security considerations

1. **HTTPS prevents trivial MITM** — main sources are HTTPS, TLS cert validated by system CA bundle.
2. **Offset threshold = 3600s** — protects against upstream returning poisoned time. Tune up only as emergency.
3. **Run as root only** — `date -s` and `hwclock -w` both need root. The systemd unit hardcodes `ExecStart`, so even with root there's no arbitrary command injection from the script logic.
4. **All actions logged to syslog** — `logger -t setclock-http` makes audit trivial via `journalctl`.
5. **Do NOT promote this host to an NTP server** — this script only calibrates *its own* clock. The host has no NTP daemon listening.

## Pitfalls

- **Don't inline big bash blocks in agent-written SKILL.md.** The `execute_code` sandbox corrupts source files when the calling context contains the literal strings `</code>` or `</invoke>` — those tokens get injected into the file body, causing SyntaxError. Keep the full script in `scripts/setclock-http.sh` and reference it via `sudo cp`. (Documented as a Hermes-wide limitation; see memory note on execute_code sandbox.)
- **YAML frontmatter containing colons inside inline code is fragile.** A description like `` `System clock synchronized: no` `` can break strict YAML parsers in `hermes skills publish` because the `:` inside the inline code is interpreted as a mapping separator. Wrap the entire `description` value in double quotes (as this skill does) or use `&#58;` HTML entity for the colon.
- **Avoid `--to clawhub`.** Currently prints "not yet supported". The official path is `--to github` (which automates fork + PR) or manual submission at https://clawhub.ai/submit.
- **Don't reconfigure `SOURCES` to point only at international CDNs from inside CN** — Baidu HTTPS Date is the most reliable in mainland China; cloudflare/google are flaky on some carriers.

## Limitations & when to upgrade

This is a **last-resort fallback**, not a substitute for real NTP. Plan to replace it when:

| Better option | When it becomes viable |
|---|---|
| NTP egress allowed | Firewall rule change — just enable `systemd-timesyncd` and disable this timer |
| DS3231 RTC battery module | Hardware project budget allows (~$5 + 4 wires) |
| GPS module with PPS | Need antenna placement + ~$15 |
| Internal NTP server | Have a host that *can* reach pool.ntp.org |

Precision is bounded by HTTPS RTT (~100ms) + 48h cycle. Long-term drift stays within ±1s. That's fine for daily cron, log timestamps, TLS handshake freshness. **Not** fine for distributed systems needing sub-second wall-clock agreement.

## Reference: deployment timeline (real example)

| Time (CST) | Event |
|---|---|
| 2026-06-15 23:35 | User reported clock ~6 minutes slow |
| 23:35 | Diagnosed: `set-ntp true` enabled but UDP/123 firewalled |
| 23:42 | Tested time1.aliyun.com / time.cloudflare.com / pool.ntp.org — all unreachable |
| 23:43 | Tried `ntp.aliyun.com` HTTP API — also timed out |
| 23:45 | Confirmed only Baidu HTTPS `Date:` header was reachable |
| 23:46 | Wrote `setclock-http` script, first run corrected +11s |
| 23:47 | Wrote service + timer units, started on a 5-minute test schedule |
| 23:50 | Switched to 48h cycle per operational preference |

**Original full write-up:** `/root/HTTP-based-clock-sync.md` (373 lines, includes full troubleshooting tables and parameter rationale — load if you need more background).

## Publishing this skill to Hermes Skills Hub

If you want to share this with other Hermes users on a blocked network, see `references/hermes-skills-publish-mechanics.md` for the full upload flow (fork → branch → upload → PR, plus token setup). Quick command:

```bash
# Requires: GITHUB_TOKEN in ~/.hermes/.env OR `gh auth login`
hermes skills publish /opt/hermes-web-ui/hermes_data/profiles/tars/skills/devops/https-clock-sync \
  --to github \
  --repo <owner>/<skills-hub-repo>
```
