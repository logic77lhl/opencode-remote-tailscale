[CmdletBinding()]
param(
    [int]$Port = 28894,
    [switch]$NoFunnel,
    [switch]$NoQr,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\common.ps1"

$repoRoot = Split-Path -Parent $PSScriptRoot
$assetDir = Join-Path $repoRoot "assets"

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host "  OpenCode Remote - restore / new login QR" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor DarkCyan

$openCode = Get-OpenCodePath
if (-not $openCode) {
    Write-Fail "OpenCode CLI not found. Run npm install -g @opencode/cli"
    exit 1
}

$tailscale = Get-TailscalePath
if (-not $tailscale) {
    Write-Fail "Tailscale not found. Run winget install --id Tailscale.Tailscale -e"
    exit 1
}

Write-Step "Checking Tailscale"
$state = Get-TailscaleState $tailscale
if (-not $state -or -not $state.Self -or -not $state.Self.DNSName) {
    if ($DryRun) {
        Write-Warn "Dry run: Tailscale is not logged in."
    } else {
        Write-Fail "Tailscale is not logged in. Run: tailscale login"
        exit 1
    }
}

$publicUrl = $null
if ($state -and $state.Self -and $state.Self.DNSName) {
    $publicUrl = Get-PublicUrl $state
    Write-Ok $publicUrl
} else {
    $publicUrl = "https://<your-host>.<your-tailnet>.ts.net"
}

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

Write-Step "Checking Tailscale Serve"
if (-not (Enable-TailscaleIngress -Tailscale $tailscale -Port $Port -Mode serve -DryRun:$DryRun)) {
    exit 1
}

if (-not $NoFunnel) {
    Write-Step "Checking Tailscale Funnel"
    if (-not (Enable-TailscaleIngress -Tailscale $tailscale -Port $Port -Mode funnel -DryRun:$DryRun)) {
        exit 1
    }
}

Write-Step "Waiting for HTTPS"
if ($DryRun) {
    Write-Warn "Dry run: skipping reachability check."
} else {
    $code = Wait-Https -Url $publicUrl -TimeoutSec 60
    if (-not $code) {
        Write-Fail "The URL did not respond. Check: tailscale serve status"
        exit 1
    }
    Write-Ok "HTTP $code"
}

Write-Step "Creating a new login link"
$link = $null
if ($DryRun) {
    $link = "https://<your-host>.<your-tailnet>.ts.net/auth/connect/<token>"
    Write-Warn "Dry run: link not generated."
} else {
    $link = New-PairLink -OpenCode $openCode -Url $publicUrl
    if (-not $link) {
        Write-Fail "Could not generate a pair link."
        exit 1
    }
    Write-Ok "Link created"
    Copy-ToClipboard $link
}

if (-not $NoQr -and -not $DryRun) {
    Show-Qr -Link $link -AssetDir $assetDir | Out-Null
}

Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Fixed URL : $publicUrl" -ForegroundColor White
Write-Host "  Login link: $link" -ForegroundColor White
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  One-time link, valid for 5 minutes. Link copied to clipboard." -ForegroundColor Yellow
Write-Host ""
