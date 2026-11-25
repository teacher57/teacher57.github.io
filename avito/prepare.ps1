# avito: prepare a Windows PC for BOT BRO / HUB BRO.
# Installs ONLY what is missing: Tailscale, OpenSSH Server, Node.js 20+. Anything already installed is left as it is.
# Then: lets the admin's Mac in over SSH (adds its public key), joins Tailscale, prints what deploy.sh needs.
#
# Every client has his OWN Tailscale network (his own free/paid Tailscale account). Run in PowerShell **as
# Administrator** on the client's PC; a browser opens -> the client signs in to HIS Tailscale account:
#   irm https://teacher57.github.io/avito/prepare.ps1 | iex
# Then the client shares this PC with the admin (Tailscale admin console -> Machines -> this PC -> Share -> the
# admin's e-mail). A shared PC can't reach the admin's devices; the admin can reach it.
# Options (run as: & ([scriptblock]::Create((irm https://teacher57.github.io/avito/prepare.ps1))) -Option ...):
#   -AuthKey tskey-auth-...   join with an auth key from the client's Tailscale (no browser)
#   -CheckOnly                only report what is installed, change nothing
#   -PublicKey "ssh-ed25519 AAAA... name"   a different admin key
# A downloaded file runs the same: .\prepare.ps1 -CheckOnly
param(
    [string]$AuthKey = "",
    [switch]$OwnDevice,   # kept for old instructions: same as the default now
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
    if ($st -and $st.BackendState -eq "Running") {
        Skip "this PC is in Tailscale ($($st.CurrentTailnet.Name))"
    } elseif ($CheckOnly) {
        Todo "join Tailscale (state: $(if ($st) { $st.BackendState } else { 'unknown' }))"
    } else {
        $up = @("up", "--unattended")
        if ($AuthKey) { $up += "--auth-key=$AuthKey" }
        else { Say "   joining Tailscale: a browser window opens - sign in to YOUR (the shop's) Tailscale account" Yellow }
        & $ts @up
        if ($LASTEXITCODE -ne 0) { throw "tailscale up failed$(if ($AuthKey) { ' (is the key valid and not used/expired?)' })" }
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
# BOT BRO license device code: the same as bot/bot_license.py device_code()
#   = first 20 hex of SHA-256("bot-bro-device:" + MachineGuid in lower case), upper case, groups of 5.
$device = ""
try {
    $guid = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid).MachineGuid.Trim().ToLower()
    $sha = [Security.Cryptography.SHA256]::Create()
    $hex = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("bot-bro-device:" + $guid)) | ForEach-Object { $_.ToString("x2") })
    $h = $hex.Substring(0, 20).ToUpper()
    $device = ($h.Substring(0, 5), $h.Substring(5, 5), $h.Substring(10, 5), $h.Substring(15, 5)) -join "-"
} catch { $device = "(could not read MachineGuid)" }
Say ""
Say "   BOT BRO license device code:  $device" Green
Say ""
Say "   NEXT - share this PC with the admin (so he can install over SSH):" Yellow
Say "     1. the Tailscale page 'Machines' opens now (sign in to YOUR Tailscale account if asked)" Yellow
Say "     2. find '$($env:COMPUTERNAME.ToLower())' -> the '...' menu on its row -> Share" Yellow
Say "     3. enter the admin's e-mail -> Share. The admin accepts the invite." Yellow
Say ""
Say "   Send the admin:  user $user, address $ip, device code $device" Green
Say "   Admin's Mac:  ./deploy.sh $user@$ip --bot --hub" Green
if (-not $CheckOnly) {
    try { Start-Process "https://login.tailscale.com/admin/machines" } catch { Say "   open https://login.tailscale.com/admin/machines in a browser" Yellow }
}
