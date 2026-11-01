[CmdletBinding()]
param(
    [int]$Port = 28894,
    [switch]$NoFunnel,
    [switch]$NoAutostart,
    [switch]$NoQr,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\common.ps1"

$repoRoot = Split-Path -Parent $PSScriptRoot
$assetDir = Join-Path $repoRoot "assets"

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host "  OpenCode Remote - one-time setup (Tailscale)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor DarkCyan

# ---------------------------------------------------------------- OpenCode
Write-Step "Locating OpenCode CLI"
$openCode = Get-OpenCodePath
if (-not $openCode) {
    Write-Fail "OpenCode CLI not found."
    Write-Host ""
    Write-Host "  Install it first:" -ForegroundColor Yellow
    Write-Host "    npm install -g @opencode/cli" -ForegroundColor White
    Write-Host ""
    Write-Host "  Then run this script again."
    exit 1
}
Write-Ok $openCode

# ---------------------------------------------------------------- Tailscale
Write-Step "Locating Tailscale"
$tailscale = Get-TailscalePath
if (-not $tailscale) {
    Write-Fail "Tailscale not found."
    Write-Host ""
    Write-Host "  Install it first:" -ForegroundColor Yellow
    Write-Host "    winget install --id Tailscale.Tailscale -e" -ForegroundColor White
    Write-Host "  Then sign in from the Tailscale tray icon and run this script again."
    exit 1
}
Write-Ok $tailscale

# ---------------------------------------------------------------- Login
Write-Step "Checking Tailscale login"
$state = Ensure-TailscaleLogin -Tailscale $tailscale -DryRun:$DryRun
if (-not $state) {
    if ($DryRun) {
        Write-Warn "Dry run: skipping login check."
    } else {
        Write-Fail "Tailscale login did not complete. Run 'tailscale login' and retry."
        exit 1
    }
}

$publicUrl = $null
if ($state) {
    $publicUrl = Get-PublicUrl $state
    if (-not $publicUrl) {
        Write-Fail "Could not read the Tailscale DNS name."
        exit 1
    }
    Write-Ok $publicUrl
} else {
    $publicUrl = "https://<your-host>.<your-tailnet>.ts.net"
}

# ---------------------------------------------------------------- Service
Write-Step "Starting OpenCode background service"
$serviceUrl = Ensure-OpenCodeService -OpenCode $openCode -Port $Port -DryRun:$DryRun
if (-not $serviceUrl) {
    Write-Fail "Could not start the OpenCode service."
    exit 1
}
if ($serviceUrl -match ":(\d+)") {
    $Port = [int]$Matches[1]
}
Write-Ok "$serviceUrl (port $Port)"

# ---------------------------------------------------------------- Ingress
Write-Step "Enabling Tailscale Serve (tailnet-only HTTPS)"
if (-not (Enable-TailscaleIngress -Tailscale $tailscale -Port $Port -Mode serve -DryRun:$DryRun)) {
    exit 1
}

if (-not $NoFunnel) {
    Write-Step "Enabling Tailscale Funnel (public HTTPS)"
    if (-not (Enable-TailscaleIngress -Tailscale $tailscale -Port $Port -Mode funnel -DryRun:$DryRun)) {
        exit 1
    }
} else {
    Write-Warn "Funnel disabled. The URL will only work on devices in your tailnet."
}

# ---------------------------------------------------------------- Reachability
Write-Step "Waiting for HTTPS to become reachable"
if ($DryRun) {
    Write-Warn "Dry run: skipping reachability check."
} else {
    $code = Wait-Https -Url $publicUrl -TimeoutSec 90
    if (-not $code) {
        Write-Fail "The public URL did not respond. Check 'tailscale serve status'."
        exit 1
    }
    Write-Ok "HTTP $code"
}

# ---------------------------------------------------------------- Autostart
if (-not $NoAutostart) {
    Write-Step "Installing logon autostart for the OpenCode service"
    if ($DryRun) {
        Write-Warn "Dry run: would write opencode-remote-service.vbs to the Startup folder."
    } else {
        $vbs = Install-Autostart -OpenCode $openCode
        Write-Ok $vbs
    }
}

# ---------------------------------------------------------------- Pair link
Write-Step "Creating a one-time login link"
$link = $null
if ($DryRun) {
    $link = "https://<your-host>.<your-tailnet>.ts.net/auth/connect/<token>"
    Write-Warn "Dry run: link not generated."
} else {
    $link = New-PairLink -OpenCode $openCode -Url $publicUrl
    if (-not $link) {
        Write-Fail "Could not generate a pair link. Try: opencode pair --url $publicUrl"
        exit 1
    }
    Write-Ok "Link created"
    Copy-ToClipboard $link
}

# ---------------------------------------------------------------- QR
$qrShown = $false
if (-not $NoQr -and -not $DryRun) {
    $qrShown = Show-Qr -Link $link -AssetDir $assetDir
}

# ---------------------------------------------------------------- Summary
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Ready" -ForegroundColor Green
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Fixed URL : $publicUrl" -ForegroundColor White
Write-Host "  Login link: $link" -ForegroundColor White
Write-Host ""
if ($qrShown) {
    Write-Host "  QR code opened in your browser." -ForegroundColor Yellow
} else {
    Write-Host "  Open the login link on your phone (one-time, 5 minutes)." -ForegroundColor Yellow
}
Write-Host "  Link is also in your clipboard." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "    1. Scan / open the link on your phone."
Write-Host "    2. Add the fixed URL to your home screen."
Write-Host "    3. Read docs/SECURITY.md before exposing Funnel long-term."
Write-Host ""
if (-not $NoFunnel) {
    Write-Host "  Funnel is public. Disable it when you do not need it:" -ForegroundColor DarkGray
    Write-Host "    tailscale funnel --https=443 off" -ForegroundColor DarkGray
    Write-Host "    tailscale serve --bg $Port" -ForegroundColor DarkGray
    Write-Host ""
}
