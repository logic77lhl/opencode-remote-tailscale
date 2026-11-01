[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$StopService,
    [switch]$ResetIngress,
    [int]$Port = 28894,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\common.ps1"

Write-Host ""
Write-Host "OpenCode Remote - uninstall helper" -ForegroundColor Cyan
Write-Host ""

if (-not $Yes -and -not $DryRun) {
    Write-Host "This will remove the logon autostart script." -ForegroundColor Yellow
    if ($ResetIngress) {
        Write-Host "It will also turn off Tailscale Serve/Funnel on port 443." -ForegroundColor Yellow
    }
    if ($StopService) {
        Write-Host "It will also stop the OpenCode background service." -ForegroundColor Yellow
    }
    $answer = Read-Host "Continue? [y/N]"
    if ($answer -notmatch "^(y|yes)$") {
        Write-Host "Cancelled."
        exit 0
    }
}

Write-Step "Removing logon autostart"
if ($DryRun) {
    Write-Warn "Dry run: would remove %APPDATA%\...\Startup\opencode-remote-service.vbs"
} else {
    if (Remove-Autostart) {
        Write-Ok "Removed opencode-remote-service.vbs"
    } else {
        Write-Ok "No autostart script found (already clean)"
    }
}

if ($ResetIngress) {
    Write-Step "Turning off Tailscale Funnel/Serve on port 443"
    $tailscale = Get-TailscalePath
    if (-not $tailscale) {
        Write-Fail "Tailscale not found; skipping ingress cleanup."
    } elseif ($DryRun) {
        Write-Warn "Dry run: would run 'tailscale funnel --https=443 off' and 'tailscale serve --https=443 off'"
    } else {
        Invoke-Captured -FilePath $tailscale -Arguments @("funnel", "--https=443", "off") -TimeoutSec 20 | Out-Null
        Invoke-Captured -FilePath $tailscale -Arguments @("serve", "--https=443", "off") -TimeoutSec 20 | Out-Null
        Write-Ok "Ingress configuration removed (if it existed)"
    }
}

if ($StopService) {
    Write-Step "Stopping OpenCode background service"
    $openCode = Get-OpenCodePath
    if (-not $openCode) {
        Write-Fail "OpenCode CLI not found; skipping service stop."
    } elseif ($DryRun) {
        Write-Warn "Dry run: would run 'opencode service stop'"
    } else {
        Invoke-Captured -FilePath $openCode -Arguments @("service", "stop") -TimeoutSec 30 | Out-Null
        Write-Ok "Service stopped"
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Your OpenCode data was NOT deleted. It lives in:" -ForegroundColor DarkGray
Write-Host "  %USERPROFILE%\.local\share\opencode" -ForegroundColor DarkGray
Write-Host "  %USERPROFILE%\.local\state\opencode" -ForegroundColor DarkGray
Write-Host ""
