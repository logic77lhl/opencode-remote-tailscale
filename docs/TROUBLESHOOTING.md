# Troubleshooting

## 1. First checks

```powershell
$ts = "C:\Program Files\Tailscale\tailscale.exe"

& $ts status                 # logged in? device online?
& $ts serve status           # Serve / Funnel configured?
opencode service status      # background service running?
```

Expected:

- `tailscale status` shows `100.x.x.x  <host>  <account>  windows`
- `tailscale serve status` shows `https://<host>.<tailnet>.ts.net (Funnel on)` and a proxy to `127.0.0.1:28894`
- `opencode service status` prints `http://127.0.0.1:28894`

If all three are correct, the URL should work.

---

## 2. Common issues

### `Importing a module script failed`

The browser loaded the HTML but failed to load a JavaScript module. Usually one of:

1. You opened an **old home-screen icon** that points to a dead hostname
2. You opened the link in **WeChat / QQ / an in-app browser**
3. The browser cached a broken page

Fix:

- Delete the old home-screen icon
- Scan with the **system camera**, open in **Safari / Chrome**
- Clear website data for `*.ts.net`, or use a private window
- Re-run `scripts/restore.ps1` for a fresh link

This is also what you see if you try to use a **Cloudflare quick tunnel** with OpenCode — quick tunnels buffer SSE, so the UI never finishes loading. Use Tailscale instead.

### 401 / "unauthenticated"

The pair link is single-use and expires after 5 minutes.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\restore.ps1
```

If it still fails, use a private window — the browser may be replaying an old request.

### 502 / 503

The OpenCode background service is not running.

```powershell
opencode service status
opencode service start
```

Or run `scripts/restore.ps1`, which starts it automatically.

If this happens after a reboot, the PC may be sitting at the **Windows lock screen** — the logon autostart script does not run until you sign in.

### `Funnel is not enabled on your tailnet`

Tailscale requires a one-time opt-in for Serve/Funnel.

`setup.ps1` / `restore.ps1` print a link like:

```
https://login.tailscale.com/f/funnel?node=...
```

Open it, enable Funnel, then press Enter in the terminal. The script retries automatically.

### `Logged out` / `NeedsLogin`

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" login
```

Sign in with the same account, then re-run `restore.ps1`.

### URL does not resolve / DNS error

- Check `tailscale status`; the device must be online
- Check `tailscale serve status`; Funnel must be on
- Try `nslookup <host>.<tailnet>.ts.net 1.1.1.1`
- If Funnel was just enabled, wait 30–60 seconds

### Very slow first load

The first load pulls ~2.9 MB of JS/CSS through the public Funnel ingress. Later loads use the browser cache.

For lower latency on Android:

1. Install the Tailscale Android app
2. Sign in with the same account
3. Open the same `https://<host>.<tailnet>.ts.net` URL — MagicDNS routes it over the tailnet

### Home-screen icon opens a blank page

The hostname changed (for example after renaming the PC or reinstalling Tailscale). Delete the icon, run `restore.ps1`, and add it again with the new URL.

### Port already in use

Check what owns the port:

```powershell
Get-NetTCPConnection -LocalPort 28894 -State Listen |
  Select-Object LocalAddress, LocalPort, OwningProcess
```

Stop the stale process, then run `restore.ps1`.

### `opencode pair` prints garbage / no link

Make sure the OpenCode service is running first:

```powershell
opencode service status
opencode service start
```

Then:

```powershell
opencode pair --url https://<host>.<tailnet>.ts.net
```

### The page loads but the session list spins forever

This is the SSE symptom. Check the browser console for:

```
[global-sdk] event stream disconnected
```

Causes:

- You are using a **Cloudflare quick tunnel** (not supported)
- An intermediate proxy is buffering `text/event-stream`
- The OpenCode service was restarted mid-request

Use Tailscale Serve/Funnel and reload. If it persists, restart the service:

```powershell
opencode service restart
```

---

## 3. Reset Serve / Funnel

Turn everything off for port 443:

```powershell
$ts = "C:\Program Files\Tailscale\tailscale.exe"
& $ts funnel --https=443 off
& $ts serve --https=443 off
```

Re-enable:

```powershell
& $ts serve --bg 28894
& $ts funnel --bg 28894
```

Check:

```powershell
& $ts serve status
```

---

## 4. Logs and data

| Item | Location |
|---|---|
| OpenCode data | `%USERPROFILE%\.local\share\opencode` |
| OpenCode state | `%USERPROFILE%\.local\state\opencode` |
| Service config + password | `%USERPROFILE%\.local\state\opencode\service.json` |
| Autostart script | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\opencode-remote-service.vbs` |

Tailscale logs are in the Tailscale tray menu (`Logs`), or Windows Event Viewer under `Tailscale`.

---

## 5. Still stuck?

Collect:

1. Output of the three status commands in section 1
2. The exact browser error text / screenshot
3. Which browser and OS version
4. Whether Funnel or Serve-only is enabled

Open an issue with the above, **without** your password, pair links, or full hostname if you prefer.
