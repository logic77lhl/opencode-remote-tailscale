# Shared helpers for OpenCode Remote (Tailscale).
# ASCII only, Windows PowerShell 5.1 compatible.

$ErrorActionPreference = "Stop"

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Ok([string]$Text) {
    Write-Host "    OK  $Text" -ForegroundColor Green
}

function Write-Warn([string]$Text) {
    Write-Host "    !!  $Text" -ForegroundColor Yellow
}

function Write-Fail([string]$Text) {
    Write-Host "    XX  $Text" -ForegroundColor Red
}

function Get-OpenCodePath {
    $candidates = @(
        (Join-Path $env:APPDATA "npm\node_modules\@opencode\cli\bin\opencode.exe"),
        (Join-Path $env:LOCALAPPDATA "npm\node_modules\@opencode\cli\bin\opencode.exe")
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }

    $cmd = Get-Command opencode -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.Source -like "*.exe") { return $cmd.Source }
        $shimDir = Split-Path $cmd.Source -Parent
        $guess = Join-Path $shimDir "node_modules\@opencode\cli\bin\opencode.exe"
        if (Test-Path $guess) { return $guess }
        return $cmd.Source
    }
    return $null
}

function Get-TailscalePath {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Tailscale\tailscale.exe")
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Tailscale\tailscale.exe")
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# Run a process with a timeout, capture stdout + stderr, never block forever.
function Invoke-Captured {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSec = 30
    )

    $stamp = [guid]::NewGuid().ToString("N")
    $out = Join-Path $env:TEMP "opencode-remote-$stamp.out"
    $err = Join-Path $env:TEMP "opencode-remote-$stamp.err"

    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments `
        -RedirectStandardOutput $out -RedirectStandardError $err `
        -WindowStyle Hidden -PassThru

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }

    $timedOut = -not $p.HasExited
    if ($timedOut) {
        try { $p.Kill() } catch { }
    }

    $text = ""
    if (Test-Path $out) { $text += (Get-Content $out -Raw -ErrorAction SilentlyContinue) }
    if (Test-Path $err) { $text += "`n" + (Get-Content $err -Raw -ErrorAction SilentlyContinue) }
    Remove-Item $out, $err -Force -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        Text     = $text
        TimedOut = $timedOut
        ExitCode = $(if ($timedOut) { $null } else { $p.ExitCode })
    }
}

function Get-TailscaleState {
    param([Parameter(Mandatory = $true)][string]$Tailscale)

    $r = Invoke-Captured -FilePath $Tailscale -Arguments @("status", "--json") -TimeoutSec 20
    $t = $r.Text.Trim()
    if (-not $t.StartsWith("{")) { return $null }
    try { return $t | ConvertFrom-Json } catch { return $null }
}

# Returns a Tailscale status object, or $null if login did not complete.
function Ensure-TailscaleLogin {
    param(
        [Parameter(Mandatory = $true)][string]$Tailscale,
        [switch]$DryRun
    )

    $state = Get-TailscaleState $Tailscale
    if ($state -and $state.Self -and $state.Self.DNSName) {
        return $state
    }

    Write-Warn "Tailscale is not logged in."
    if ($DryRun) {
        Write-Step "Would run: tailscale login (and wait for browser login)"
        return $null
    }

    $stamp = [guid]::NewGuid().ToString("N")
    $out = Join-Path $env:TEMP "opencode-remote-login-$stamp.out"
    $err = Join-Path $env:TEMP "opencode-remote-login-$stamp.err"
    $p = Start-Process -FilePath $Tailscale -ArgumentList @("login") `
        -RedirectStandardOutput $out -RedirectStandardError $err `
        -WindowStyle Hidden -PassThru

    $url = $null
    for ($i = 0; $i -lt 30 -and -not $url; $i++) {
        Start-Sleep -Milliseconds 500
        $text = ""
        if (Test-Path $out) { $text += (Get-Content $out -Raw -ErrorAction SilentlyContinue) }
        if (Test-Path $err) { $text += (Get-Content $err -Raw -ErrorAction SilentlyContinue) }
        $m = [regex]::Match($text, "https://login\.tailscale\.com/\S+")
        if ($m.Success) { $url = $m.Value }
        if ($p.HasExited -and $url) { break }
    }

    if ($url) {
        Write-Host ""
        Write-Host "    Open this link and sign in:" -ForegroundColor Yellow
        Write-Host "    $url" -ForegroundColor White
        try { Start-Process $url } catch { }
    } else {
        Write-Warn "No login URL was printed. Run 'tailscale login' manually."
    }

    for ($i = 0; $i -lt 150; $i++) {
        Start-Sleep -Seconds 2
        $state = Get-TailscaleState $Tailscale
        if ($state -and $state.Self -and $state.Self.DNSName) {
            if (-not $p.HasExited) { try { $p.Kill() } catch { } }
            Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
            return $state
        }
    }

    if (-not $p.HasExited) { try { $p.Kill() } catch { } }
    Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    return $null
}

function Get-PublicUrl {
    param([Parameter(Mandatory = $true)]$State)
    $dns = $State.Self.DNSName
    if (-not $dns) { return $null }
    return "https://" + $dns.TrimEnd(".")
}

function Ensure-OpenCodeService {
    param(
        [Parameter(Mandatory = $true)][string]$OpenCode,
        [int]$Port = 28894,
        [switch]$DryRun
    )

    $r = Invoke-Captured -FilePath $OpenCode -Arguments @("service", "status") -TimeoutSec 20
    if ($r.Text -match "http://127\.0\.0\.1:(\d+)") {
        return $Matches[0]
    }

    Write-Warn "OpenCode service is not running. Starting it..."
    if ($DryRun) {
        return "http://127.0.0.1:$Port"
    }

    Invoke-Captured -FilePath $OpenCode -Arguments @("service", "start") -TimeoutSec 60 | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        $r = Invoke-Captured -FilePath $OpenCode -Arguments @("service", "status") -TimeoutSec 15
        if ($r.Text -match "http://127\.0\.0\.1:(\d+)") {
            return $Matches[0]
        }
    }
    return $null
}

# Enable Tailscale Serve or Funnel on a local port.
# Handles the "not enabled on your tailnet" flow: prints the enable URL,
# opens it, waits for the user, then retries.
function Enable-TailscaleIngress {
    param(
        [Parameter(Mandatory = $true)][string]$Tailscale,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][ValidateSet("serve", "funnel")][string]$Mode,
        [switch]$DryRun
    )

    $argList = @($Mode, "--bg", "$Port")

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        if ($DryRun) {
            Write-Step ("Would run: tailscale {0} --bg {1}" -f $Mode, $Port)
            return $true
        }

        $r = Invoke-Captured -FilePath $Tailscale -Arguments $argList -TimeoutSec 12
        $text = $r.Text

        if ($text -match "not enabled") {
            Write-Warn ("Tailscale {0} is not enabled for this tailnet." -f $Mode)
            $m = [regex]::Match($text, "https://login\.tailscale\.com/\S+")
            if ($m.Success) {
                Write-Host "    Open this link and enable it:" -ForegroundColor Yellow
                Write-Host "    $($m.Value)" -ForegroundColor White
                try { Start-Process $m.Value } catch { }
            }
            Read-Host "    Press Enter after enabling it in the browser" | Out-Null
            continue
        }

        if ($text -match "not logged in|Logged out|NeedsLogin") {
            Write-Fail "Tailscale is not logged in. Run 'tailscale login' first."
            return $false
        }

        if ($text -match "error|failed|denied" -and $text -notmatch "Available|started|Funnel on") {
            Write-Fail ("tailscale {0} failed:" -f $Mode)
            Write-Host $text
            return $false
        }

        Write-Ok ("{0} is configured on port {1}" -f $Mode, $Port)
        return $true
    }

    Write-Fail ("Could not enable Tailscale {0}. Enable it in the admin console and retry." -f $Mode)
    return $false
}

function Wait-Https {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSec = 90
    )

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds($TimeoutSec)

    while ((Get-Date) -lt $deadline) {
        if ($curl) {
            $code = (& $curl.Source -s -o NUL -w "%{http_code}" --max-time 10 $Url 2>$null | Out-String).Trim()
        } else {
            $code = ""
            try {
                $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
                $code = [string]$resp.StatusCode
            } catch {
                if ($_.Exception.Response) { $code = [string][int]$_.Exception.Response.StatusCode }
            }
        }

        if ($code -and $code -notin @("000", "502", "503", "504")) {
            return $code
        }
        Start-Sleep -Seconds 1
    }
    return $null
}

function New-PairLink {
    param(
        [Parameter(Mandatory = $true)][string]$OpenCode,
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSec = 20
    )

    $r = Invoke-Captured -FilePath $OpenCode -Arguments @("pair", "--url", $Url) -TimeoutSec $TimeoutSec
    $m = [regex]::Match($r.Text, "https://[^\s]+/auth/connect/[A-Za-z0-9_\-]+")
    if ($m.Success) { return $m.Value }
    return $null
}

# Local QR page: no CDN, no Python, no network. Uses the vendored qrcode.min.js.
function Show-Qr {
    param(
        [Parameter(Mandatory = $true)][string]$Link,
        [Parameter(Mandatory = $true)][string]$AssetDir
    )

    $js = Join-Path $AssetDir "qrcode.min.js"
    if (-not (Test-Path $js)) { return $false }

    # Inline the library so the generated page is self-contained
    # (no file:// script loading restrictions, no network, no CDN).
    $jsContent = (Get-Content $js -Raw) -replace "</script>", "<\/script>"
    $linkJson = $Link | ConvertTo-Json -Compress
    $linkHtml = [System.Net.WebUtility]::HtmlEncode($Link)

    $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OpenCode Remote - Login QR</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center;
         background: #0f1115; color: #e6e6e6;
         font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  .card { background: #171a21; border: 1px solid #262b36; border-radius: 16px;
          padding: 28px 28px 22px; text-align: center; max-width: 420px; width: calc(100% - 40px); }
  h1 { font-size: 18px; margin: 0 0 4px; font-weight: 600; }
  p { margin: 0 0 18px; color: #9aa4b2; font-size: 13px; }
  #q { display: inline-block; background: #fff; padding: 12px; border-radius: 10px; }
  code { display: block; margin-top: 16px; padding: 10px 12px; background: #0f1115;
         border: 1px solid #262b36; border-radius: 8px; font-size: 11px;
         word-break: break-all; color: #9aa4b2; user-select: all; }
  .warn { margin-top: 14px; color: #f0b35a; font-size: 12px; }
</style>
</head>
<body>
  <div class="card">
    <h1>OpenCode Remote</h1>
    <p>Scan with the system camera. Do not open in WeChat/QQ.</p>
    <div id="q"></div>
    <code>$linkHtml</code>
    <div class="warn">One-time link. Expires in 5 minutes.</div>
  </div>
<script>
$jsContent
</script>
<script>
  new QRCode(document.getElementById("q"), {
    text: $linkJson,
    width: 320,
    height: 320,
    correctLevel: QRCode.CorrectLevel.M
  });
</script>
</body>
</html>
"@

    $out = Join-Path $env:TEMP ("opencode-remote-qr-" + [guid]::NewGuid().ToString("N") + ".html")
    [IO.File]::WriteAllText($out, $html, (New-Object System.Text.UTF8Encoding $false))
    try { Start-Process $out } catch { }
    return $true
}

function Install-Autostart {
    param([Parameter(Mandatory = $true)][string]$OpenCode)

    $startup = [Environment]::GetFolderPath("Startup")
    $vbs = Join-Path $startup "opencode-remote-service.vbs"
    $content = "' OpenCode Remote: start the background service silently at logon`r`n" +
               "Set sh = CreateObject(`"WScript.Shell`")`r`n" +
               "sh.Run `"`"`"$OpenCode`"`" service start`", 0, False`r`n"
    [IO.File]::WriteAllText($vbs, $content, [System.Text.Encoding]::ASCII)
    return $vbs
}

function Remove-Autostart {
    $startup = [Environment]::GetFolderPath("Startup")
    $vbs = Join-Path $startup "opencode-remote-service.vbs"
    if (Test-Path $vbs) {
        Remove-Item $vbs -Force
        return $true
    }
    return $false
}

function Copy-ToClipboard {
    param([Parameter(Mandatory = $true)][string]$Text)
    try { Set-Clipboard -Value $Text } catch { }
}
