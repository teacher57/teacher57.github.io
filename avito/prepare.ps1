# avito: prepare a Windows PC for BOT BRO / HUB BRO.
# Installs ONLY what is missing: Tailscale, OpenSSH Server, Node.js 20+. Anything already installed is left as it is.
# Then: lets the admin's Mac in over SSH (adds its public key), joins Tailscale, prints what deploy.sh needs.
#
# Run in PowerShell **as Administrator**. A CLIENT's PC joins Tailscale only with a one-time auth key tagged tag:client
# (the admin makes it in the Tailscale admin console; such a PC can't reach the admin's or other clients' devices):
#   & ([scriptblock]::Create((irm https://teacher57.github.io/avito/prepare.ps1))) -AuthKey tskey-auth-...
# The admin's OWN PC (browser sign-in to the admin's account, sees all his devices):
#   & ([scriptblock]::Create((irm https://teacher57.github.io/avito/prepare.ps1))) -OwnDevice
# Only report what is installed, change nothing:
#   & ([scriptblock]::Create((irm https://teacher57.github.io/avito/prepare.ps1))) -CheckOnly
# Other: -PublicKey "ssh-ed25519 AAAA... name" = a different admin key. A downloaded file runs the same: .\prepare.ps1 -AuthKey ...
# Safe to run again. Nothing here is secret: the key below is a PUBLIC key.
param(
    [string]$AuthKey = "",
    [switch]$OwnDevice,
    [string]$PublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMV6KnZUz+NL8bKoO7mqv7na4fUmkrvQ67gqLN0J6IZs admin-mac",
    [switch]$CheckOnly
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Say($text, $color = "Gray") { Write-Host $text -ForegroundColor $color }
function Step($text) { Write-Host ""; Write-Host "== $text" -ForegroundColor Cyan }
function Done($text) { Say "   ok: $text" Green }
function Skip($text) { Say "   already there: $text" DarkGreen }
function Todo($text) { Say "   would do: $text" Yellow }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw "Run PowerShell as Administrator (right click -> Run as administrator) and start again." }

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}

# winget first (id matched without case: --exact is case-sensitive and ids differ in case between winget versions);
# if winget is missing, old or can't find the package -> the vendor's official installer ($fallback scriptblock).
function Install-App($id, $what, $fallback) {
    if ($CheckOnly) { Todo "install $what"; return }
    Say "   installing $what ..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id $id --silent --accept-package-agreements --accept-source-agreements --source winget | Out-Host
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { Refresh-Path; Done "$what installed (winget)"; return }
        Say "   winget could not install $what (code $LASTEXITCODE) - using the official installer" Yellow
    } else {
        Say "   no winget - using the official installer" Yellow
    }
    & $fallback
    Refresh-Path
    Done "$what installed (official installer)"
}

function Download($url, $file) {
    $path = Join-Path $env:TEMP $file
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
    return $path
}

$TailscaleOfficial = {
    $exe = Download "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe" "tailscale-setup-latest.exe"
    $p = Start-Process -FilePath $exe -ArgumentList "/quiet" -Wait -PassThru
    Remove-Item $exe -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) { throw "Tailscale installer failed (code $($p.ExitCode))" }
}

$NodeOfficial = {
    $lts = (Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing) |
        Where-Object { $_.lts -and [int]($_.version.TrimStart("v").Split(".")[0]) -ge 20 } | Select-Object -First 1
    if (-not $lts) { throw "could not find a Node.js LTS release on nodejs.org" }
    $msi = Download "https://nodejs.org/dist/$($lts.version)/node-$($lts.version)-x64.msi" "node-lts-x64.msi"
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "Node.js installer failed (code $($p.ExitCode))" }
}

# ---------------------------------------------------------------- 1. Tailscale
Step "Tailscale"
$ts = "$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $ts) { Skip "Tailscale ($ts)" } else { Install-App "Tailscale.Tailscale" "Tailscale" $TailscaleOfficial }
if (Test-Path $ts) {
    $svc = Get-Service Tailscale -ErrorAction SilentlyContinue
    if ($svc -and $svc.StartType -ne "Automatic") {
        if ($CheckOnly) { Todo "Tailscale service -> Automatic" } else { Set-Service Tailscale -StartupType Automatic; Done "Tailscale service starts automatically" }
    }
    $st = $null
    try { $st = & $ts status --json 2>$null | ConvertFrom-Json } catch {}
    $tags = @(); if ($st -and $st.Self.Tags) { $tags = @($st.Self.Tags) }
    if ($st -and $st.BackendState -eq "Running") {
        Skip ("this PC is in Tailscale" + $(if ($tags) { " (tags: $($tags -join ', '))" } else { " (as a user's device, no tag)" }))
        if (-not $OwnDevice -and -not ($tags -contains "tag:client")) {
            Say "   WARNING: a client's PC must be in Tailscale with tag:client, otherwise it can reach the admin's devices." Yellow
            Say "   Fix: run again with -AuthKey tskey-... (a one-time key with tag:client) - it re-joins the PC with the tag." Yellow
            if ($AuthKey -and -not $CheckOnly) {
                & $ts up --unattended --force-reauth --auth-key=$AuthKey
                if ($LASTEXITCODE -ne 0) { throw "tailscale up failed" }
                Done "re-joined Tailscale with the key's tag"
            }
        }
    } elseif ($CheckOnly) {
        Todo "join Tailscale (state: $(if ($st) { $st.BackendState } else { 'unknown' }))"
    } elseif ($AuthKey) {
        & $ts up --unattended --auth-key=$AuthKey
        if ($LASTEXITCODE -ne 0) { throw "tailscale up failed (is the key one-time and not used/expired?)" }
        Done "joined Tailscale with the key (works without a signed-in user)"
    } elseif ($OwnDevice) {
        Say "   joining Tailscale: a browser window opens - sign in with the admin's Tailscale account" Yellow
        & $ts up --unattended
        if ($LASTEXITCODE -ne 0) { throw "tailscale up failed" }
        Done "joined Tailscale as the admin's own device"
    } else {
        throw ("Tailscale: a client's PC needs a one-time key with tag:client. Ask the admin for it and run:`n" +
               "  & ([scriptblock]::Create((irm https://teacher57.github.io/avito/prepare.ps1))) -AuthKey tskey-auth-...")
    }
}

# ---------------------------------------------------------------- 2. OpenSSH Server
Step "SSH server"
$cap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" | Select-Object -First 1
if ($cap.State -eq "Installed") { Skip "OpenSSH Server" }
elseif ($CheckOnly) { Todo "install OpenSSH Server" }
else { Say "   installing OpenSSH Server ..."; Add-WindowsCapability -Online -Name $cap.Name | Out-Null; Done "OpenSSH Server installed" }
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshd) {
    if ($sshd.StartType -ne "Automatic") { if ($CheckOnly) { Todo "sshd -> Automatic" } else { Set-Service sshd -StartupType Automatic; Done "sshd starts automatically" } }
    if ($sshd.Status -ne "Running") { if ($CheckOnly) { Todo "start sshd" } else { Start-Service sshd; Done "sshd started" } }
    else { Skip "sshd running" }
}
$rule = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
    $_.Enabled -eq "True" -and $_.Direction -eq "Inbound" -and ($_ | Get-NetFirewallPortFilter).LocalPort -eq "22" }
if ($rule) { Skip "firewall allows port 22" }
elseif ($CheckOnly) { Todo "open port 22 in the firewall" }
else { New-NetFirewallRule -Name "sshd-avito" -DisplayName "OpenSSH Server (avito)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null; Done "port 22 open" }

# Admin key. For Administrators Windows reads ONLY C:\ProgramData\ssh\administrators_authorized_keys (strict ACL).
$keyBody = ($PublicKey -split "\s+")[0..1] -join " "
$file = "$env:ProgramData\ssh\administrators_authorized_keys"
$present = (Test-Path $file) -and ((Get-Content $file -ErrorAction SilentlyContinue) -match [regex]::Escape($keyBody))
if ($present) { Skip "admin's Mac key" }
elseif ($CheckOnly) { Todo "add the admin's Mac key to $file" }
else {
    New-Item -ItemType Directory -Force -Path (Split-Path $file) | Out-Null
    Add-Content -Path $file -Value $PublicKey -Encoding ascii
    icacls.exe $file /inheritance:r | Out-Null
    icacls.exe $file /grant "SYSTEM:F" /grant "BUILTIN\Administrators:F" | Out-Null
    Done "admin's Mac key added"
}

# ---------------------------------------------------------------- 3. Node.js
Step "Node.js"
$nodeOk = $false
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    $v = (& node -v) -replace "^v", ""
    if ([version]$v -ge [version]"20.0") { $nodeOk = $true; Skip "Node.js $v" } else { Say "   Node.js $v is too old (need 20+)" Yellow }
}
if (-not $nodeOk) {
    if ($node) { Say "   an older Node.js is installed; upgrading it" Yellow }
    Install-App "OpenJS.NodeJS.LTS" "Node.js LTS" $NodeOfficial
}

# ---------------------------------------------------------------- summary for deploy.sh
Step "For the admin (send this to him)"
$who = (whoami) -split "\\"
$user = $who[-1]
$dns = ""
$ip = ""
if (Test-Path $ts) {
    try { $j = & $ts status --json 2>$null | ConvertFrom-Json; $dns = $j.Self.DNSName.TrimEnd("."); $ip = ($j.Self.TailscaleIPs | Select-Object -First 1) } catch {}
}
Say "   user:     $user"
Say "   profile:  $env:USERPROFILE"
Say "   computer: $env:COMPUTERNAME"
Say "   tailscale: $ip  $dns"
Say ""
Say "   On the Mac:  ./deploy.sh $user@$ip --bot --hub" Green
