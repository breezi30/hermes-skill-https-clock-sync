# v1.1.0 — 2026-06-27

Adds CI/CD automation. **No changes to the clock-sync logic.**

## What's new

- **GitHub Actions workflow** at `.github/workflows/release.yml`:
  - `validate` job runs on PRs and direct pushes to `main` (shellcheck + frontmatter lint + executable bit check)
  - `release` job runs on tag push (`v*`), reads `RELEASE_NOTES_vN.N.N.md` or falls back to `git log`
- **Concurrency control**: cancels redundant `validate` runs on PRs to save minutes
- **Prerelease detection**: tags containing `-` (e.g. `v1.1.0-rc1`) are auto-marked as prerelease
- **README**: added "Release process" section

## Upgrade

No action required. The `setclock-http` script and systemd units are unchanged.

## Install

```bash
git clone https://github.com/breezi30/hermes-skill-https-clock-sync.git
cd hermes-skill-https-clock-sync
git checkout v1.1.0
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