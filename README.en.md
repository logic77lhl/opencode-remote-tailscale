# OpenCode Remote (Tailscale)

One command turns **OpenCode** on a Windows PC into a remote workspace you can use from any phone browser.

No mobile app required. The URL is **permanent** — it survives reboots.

> Tested with Windows 11, OpenCode `2.2.5`, Tailscale `1.104.4`, PowerShell 5.1.

---

## Why Tailscale instead of a Cloudflare quick tunnel

Cloudflare **quick tunnels** buffer `text/event-stream` (SSE). OpenCode's web UI needs SSE to load the session list, so with a quick tunnel you get a page that opens but never finishes loading, plus repeated `event stream disconnected` errors.

This is documented in [cloudflared#1449](https://github.com/cloudflare/cloudflared/issues/1449): quick tunnels are demo-only and do not stream SSE. Named tunnels work, but they require a domain.

Tailscale Serve/Funnel stream correctly and give you a stable hostname.

---

## Architecture

```
Phone browser
   │ HTTPS
   ▼
Tailscale Funnel (public ingress, stable hostname)
   │ WireGuard
   ▼
tailscaled (this PC)
   │ HTTP
   ▼
OpenCode service 127.0.0.1:28894
```

- No public IP, no port forwarding, no firewall changes
- Funnel = public HTTPS (works on iPhone without an app)
- Serve = tailnet-only HTTPS (faster on Android with the Tailscale app)
- Auth = one-time pair link (5 min, single use) → 30-day cookie

---

## Requirements

| Item | Requirement |
|---|---|
| OS | Windows 10 / 11 |
| PowerShell | 5.1+ |
| OpenCode | `@opencode/cli` (tested `2.2.5`) |
| Tailscale | Free Personal account, signed in |
| Network | Access to `login.tailscale.com` and `*.ts.net` |

No Python, no domain, no extra runtime.

---

## Quick start

```powershell
# 1. OpenCode
npm install -g @opencode/cli
opencode --version

# 2. Tailscale (then sign in from the tray icon)
winget install --id Tailscale.Tailscale -e

# 3. Clone and run
git clone https://github.com/logic77lhl/opencode-remote-tailscale.git
cd opencode-remote-tailscale
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

`setup.ps1` will:

1. Locate the OpenCode CLI
2. Check Tailscale login (opens the login page if needed)
3. Start the OpenCode background service
4. Enable Serve, then Funnel
   - If the tailnet has them disabled, it prints/opens the enable link and retries after you press Enter
5. Wait until the HTTPS URL responds
6. Install a logon autostart for the OpenCode service
7. Create a one-time login link and open a local QR page

Scan the QR with the **system camera** (not WeChat/QQ), then add the fixed URL to your home screen.

---

## Daily use

| Action | How |
|---|---|
| Open | Tap the home-screen icon |
| Switch sessions | Session list in the sidebar/drawer |
| New session | Top-right button |
| Send prompts | Bottom input (voice supported) |
| Approve tools | Permission dialog |
| Phone offline/locked | Tasks keep running on the PC |

### After a reboot

Tailscale and Funnel restore automatically. The OpenCode service starts at logon via `opencode-remote-service.vbs`. If the PC is sitting at the lock screen, log in once — otherwise the URL returns 502.

### New login QR

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\restore.ps1
```

Options: `-NoQr` (link only), `-NoFunnel` (tailnet only).

---

## Security

**The OpenCode password is effectively a remote shell password.** Anyone with the password, a pair link, or a 30-day cookie can read/write files and run commands as you.

- Funnel's login page is public (password protected)
- Pair links are one-time and expire in 5 minutes
- Cookies last 30 days (`HttpOnly`, `SameSite=Lax`)
- **Changing the password revokes every existing session immediately**

Minimum hardening:

1. Enable 2FA on the Tailscale account
2. Disable Funnel when you don't need public access:
   ```powershell
   & "C:\Program Files\Tailscale\tailscale.exe" funnel --https=443 off
   & "C:\Program Files\Tailscale\tailscale.exe" serve --bg 28894
   ```
3. Lost phone: `opencode service set password "<new random password>"`
4. Enable BitLocker; avoid running OpenCode as an administrator

Full details: [docs/SECURITY.md](docs/SECURITY.md).

---

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

`-ResetIngress` turns off Serve/Funnel. `-StopService` stops OpenCode. Session data is not deleted.

---

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

| Symptom | Fix |
|---|---|
| `Importing a module script failed` | Remove the old home-screen icon; open in Safari/Chrome; clear site data |
| 401 / unauthenticated | Link expired or already used; run `restore.ps1` |
| 502 | OpenCode service is down; run `restore.ps1` |
| `Funnel is not enabled` | Open the enable link printed by the script, then retry |
| `Logged out` | `tailscale login` |
| Slow | Public Funnel path; install the Tailscale app on Android for direct access |

---

## License

MIT
