# avito: prepare a Windows PC for BOT BRO / HUB BRO.
# Installs ONLY what is missing: Tailscale, OpenSSH Server, Node.js 20+. Anything already installed is left as it is.
# Then: lets the admin's Mac in over SSH (adds its public key), joins Tailscale, prints what deploy.sh needs.
#
# Run in PowerShell **as Administrator**:
#   irm https://teacher57.github.io/avito/prepare.ps1 | iex
# Options (download the file first, then run it with parameters):
#   .\prepare.ps1 -AuthKey tskey-...      join a Tailscale network with an auth key (no browser login)
#   .\prepare.ps1 -PublicKey "ssh-ed25519 AAAA... name"   a different admin key
#   .\prepare.ps1 -CheckOnly              only report what is installed, change nothing
# Safe to run again. Nothing here is secret: the key below is a PUBLIC key.
param(
    [string]$AuthKey = "",
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

function Have-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget not found: install 'App Installer' from Microsoft Store, then run this again."
    }
}
function Winget-Install($id, $what) {
    if ($CheckOnly) { Todo "install $what (winget $id)"; return }
    Have-Winget
    Say "   installing $what ..."
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements | Out-Host
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {  # -1978335189 = already installed
        throw "winget could not install $what (code $LASTEXITCODE). Update 'App Installer' in Microsoft Store and retry."
    }
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    Done "$what installed"
}

# ---------------------------------------------------------------- 1. Tailscale
Step "Tailscale"
$ts = "$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $ts) { Skip "Tailscale ($ts)" } else { Winget-Install "tailscale.tailscale" "Tailscale" }
if (Test-Path $ts) {
    $svc = Get-Service Tailscale -ErrorAction SilentlyContinue
    if ($svc -and $svc.StartType -ne "Automatic") {
        if ($CheckOnly) { Todo "Tailscale service -> Automatic" } else { Set-Service Tailscale -StartupType Automatic; Done "Tailscale service starts automatically" }
    }
    $state = $null
    try { $state = (& $ts status --json 2>$null | ConvertFrom-Json).BackendState } catch {}
    if ($state -eq "Running") {
        Skip "this PC is in Tailscale"
    } elseif ($CheckOnly) {
        Todo "join Tailscale (state: $state)"
    } else {
        Say "   joining Tailscale: a browser window opens - sign in with the admin's Tailscale account" Yellow
        $up = @("up", "--unattended")
        if ($AuthKey) { $up += "--auth-key=$AuthKey" }
        & $ts @up
        if ($LASTEXITCODE -ne 0) { throw "tailscale up failed" }
        Done "joined Tailscale (works without a signed-in user)"
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
    Winget-Install "OpenJS.NodeJS.LTS" "Node.js LTS"
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
