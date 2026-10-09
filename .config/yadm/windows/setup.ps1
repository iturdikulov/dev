#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bootstrap a Windows Server 2025 dev machine: winget packages, Hyper-V,
    OpenSSH server restricted to trusted hosts, and a few system tweaks.

.DESCRIPTION
    Idempotent: safe to re-run. Compatible with built-in Windows PowerShell 5.1.

    SSH key: pass the public key(s) of the trusted hosts (e.g. volga's
    ~/.ssh/id_ed25519.pub from a USB stick) with -SshPublicKeyFile, now or on
    a later re-run. Password authentication stays enabled until
    administrators_authorized_keys contains at least one key.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup.ps1
    powershell -ExecutionPolicy Bypass -File .\setup.ps1 -SkipApps -SkipSystem -SshPublicKeyFile E:\id_ed25519.pub
    powershell -ExecutionPolicy Bypass -File .\setup.ps1 -SkipApps -AllowedHosts 192.168.1.169,192.168.1.50
#>
[CmdletBinding()]
param(
    # volga (static lease in ob_nm/system/etc/dnsmasq.d/ob-nm-hosts.conf)
    [string[]]$AllowedHosts = @('192.168.1.169'),
    # Appended (deduplicated) to C:\ProgramData\ssh\administrators_authorized_keys
    [string]$SshPublicKeyFile,
    [switch]$SkipApps,
    [switch]$SkipSystem,
    [switch]$SkipSsh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Failed = New-Object System.Collections.Generic.List[string]
$script:Warnings = New-Object System.Collections.Generic.List[string]
$script:RebootRequired = $false

function Write-LogInfo([string]$Message) { Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-LogWarn([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
    $script:Warnings.Add($Message)
}
function Write-LogError([string]$Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    $script:Failed.Add($Message)
}

function Test-Command([string]$Name) {
    [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Set-RegistryValue([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

# ---------------------------------------------------------------------------
# winget
# ---------------------------------------------------------------------------

# winget exit codes that mean "nothing to do"
$WingetOkCodes = @(
    0,
    -1978335189, # 0x8A15002B APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE
    -1978335135  # 0x8A150061 APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
)
$WingetRebootCodes = @(
    -1978334967, # 0x8A150109 APPINSTALLER_CLI_ERROR_INSTALL_REBOOT_REQUIRED_TO_FINISH
    -1978334966  # 0x8A15010A APPINSTALLER_CLI_ERROR_INSTALL_REBOOT_REQUIRED_FOR_INSTALL
)

function Initialize-Winget {
    if (Test-Command winget) {
        Write-LogInfo "winget is available"
        return
    }
    Write-LogInfo "winget not found; bootstrapping via Microsoft.WinGet.Client"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
    Import-Module Microsoft.WinGet.Client
    Repair-WinGetPackageManager -AllUsers -Latest
    Update-SessionPath
    if (-not (Test-Command winget)) {
        throw "winget is still unavailable after Repair-WinGetPackageManager"
    }
}

function Install-WingetPackage([string]$Id, [string]$Override = '') {
    winget list --id $Id --exact --accept-source-agreements *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-LogInfo "$Id is already installed"
        return
    }

    Write-LogInfo "Installing $Id"
    $wingetArgs = @(
        'install', '--id', $Id, '--exact',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    )
    if ($Override) {
        $wingetArgs += @('--override', $Override)
    } else {
        $wingetArgs += '--silent'
    }
    & winget @wingetArgs
    $code = $LASTEXITCODE

    if ($WingetOkCodes -contains $code) {
        return
    }
    if ($WingetRebootCodes -contains $code) {
        Write-LogWarn "$Id requires a reboot to finish installing"
        $script:RebootRequired = $true
        return
    }
    Write-LogError ("winget failed to install {0} (exit code 0x{1:X8})" -f $Id, $code)
}

$Packages = @(
    # Core CLI
    'Git.Git'
    'Neovim.Neovim'
    'junegunn.fzf'
    'BurntSushi.ripgrep.MSVC'
    'sharkdp.fd'
    'sharkdp.bat'
    'dandavison.delta'
    'Wilfred.difftastic'
    'jqlang.jq'
    'MikeFarah.yq'
    'JesseDuffield.lazygit'
    'JesseDuffield.Lazydocker'
    'j178.Prek'
    '7zip.7zip'
    'ajeetdsouza.zoxide'
    'Starship.Starship'

    # Languages & toolchains
    'Python.Python.3.14'
    'astral-sh.uv'
    'Schniz.fnm'
    'pnpm.pnpm'
    # Microsoft.VisualStudio.2022.BuildTools is installed separately (needs --override)

    # IDE & AI
    'Anysphere.Cursor'
    'JetBrains.PyCharm'
    'Anthropic.ClaudeCode'
    'OpenAI.Codex'

    # DB
    'DBeaver.DBeaver.Community'

    # Terminal, messengers
    'Microsoft.WindowsTerminal'
    'Telegram.TelegramDesktop'
    'Yandex.Messenger'

    # Network
    'aria2.aria2'
    'GNU.Wget2'
    'AnyDesk.AnyDesk'
    'LizardByte.Sunshine'
    'WiresharkFoundation.Wireshark'
    'Insecure.Nmap'
    'qBittorrent.qBittorrent'

    # Media & docs
    'shinchiro.mpv'
    'KDE.Krita'
    'Gyan.FFmpeg'
    'JohnMacFarlane.Pandoc'

    # Utilities
    'voidtools.Everything'
)

$VsBuildToolsOverride = '--quiet --wait --norestart --nocache ' +
    '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'

$ProfileMarker = '# yadm-windows: shell integrations'

function Install-Apps {
    Initialize-Winget

    foreach ($id in $Packages) {
        Install-WingetPackage $id
    }
    Install-WingetPackage 'Microsoft.VisualStudio.2022.BuildTools' $VsBuildToolsOverride

    Update-SessionPath

    if (Test-Command git) {
        git config --system core.longpaths true
    }

    # Cursor CLI is not in winget
    if (Test-Command cursor-agent) {
        Write-LogInfo "Cursor CLI is already installed"
    } else {
        Write-LogInfo "Installing Cursor CLI"
        try {
            Invoke-RestMethod 'https://cursor.com/install?win32=true' | Invoke-Expression
        } catch {
            Write-LogError "Cursor CLI install failed: $_"
        }
    }

    # Node.js LTS through fnm (mirrors runs/07_node using nvm)
    if (Test-Command fnm) {
        Write-LogInfo "Installing Node.js LTS through fnm"
        fnm install --lts
        fnm default lts-latest
    } else {
        Write-LogError "fnm is unavailable; skipping Node.js LTS"
    }

    # fnm/zoxide/starship need shell hooks to be usable
    $profilePath = $PROFILE.CurrentUserAllHosts
    $profileDir = Split-Path $profilePath
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    if ((Test-Path $profilePath) -and (Select-String -Path $profilePath -SimpleMatch $ProfileMarker -Quiet)) {
        Write-LogInfo "Shell integrations already configured in $profilePath"
    } else {
        Write-LogInfo "Adding fnm/zoxide/starship integrations to $profilePath"
        $block = @"

$ProfileMarker
if (Get-Command fnm -ErrorAction SilentlyContinue) { fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression }
if (Get-Command zoxide -ErrorAction SilentlyContinue) { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }
if (Get-Command starship -ErrorAction SilentlyContinue) { Invoke-Expression (&starship init powershell) }
"@
        Add-Content -Path $profilePath -Value $block -Encoding UTF8
    }

    Write-LogWarn "Sunshine: set the admin password at https://localhost:47990, then pair Moonlight clients"
    Write-LogWarn "Wireshark: install Npcap manually (https://npcap.com) - the free edition has no silent installer"
}

# ---------------------------------------------------------------------------
# Extras: winutil, Powershellisfun
# ---------------------------------------------------------------------------

$ProjectsDir = Join-Path $HOME 'prj'
$WinutilUrl = 'https://github.com/ChrisTitusTech/winutil/releases/latest/download/winutil.ps1'
$WinutilDir = Join-Path $env:LOCALAPPDATA 'winutil'
$WinutilScript = Join-Path $WinutilDir 'winutil.ps1'
$PowershellisfunUrl = 'https://github.com/HarmVeenstra/Powershellisfun'

function Initialize-ProjectsDir {
    if (-not (Test-Path $ProjectsDir)) {
        Write-LogInfo "Creating $ProjectsDir"
        New-Item -ItemType Directory -Path $ProjectsDir | Out-Null
    }
}

function Install-Winutil {
    # winutil is a GUI script, not a package: keep a local copy (refreshed on
    # every run) and a Start Menu shortcut that launches it elevated
    Write-LogInfo "Downloading winutil to $WinutilScript"
    try {
        if (-not (Test-Path $WinutilDir)) {
            New-Item -ItemType Directory -Path $WinutilDir | Out-Null
        }
        Invoke-WebRequest -Uri $WinutilUrl -OutFile $WinutilScript -UseBasicParsing
    } catch {
        Write-LogError "winutil download failed: $_"
        return
    }

    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'WinUtil.lnk'
    $powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process '$powershell' -Verb RunAs " +
        "-ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \`"$WinutilScript\`"'`""
    $shortcut.IconLocation = "$powershell,0"
    $shortcut.Description = 'Chris Titus Tech Windows Utility'
    $shortcut.Save()
    Write-LogInfo "winutil shortcut: $shortcutPath (or run: irm https://christitus.com/win | iex)"
}

function Update-GitRepo([string]$Url, [string]$Path) {
    if (-not (Test-Command git)) {
        Write-LogError "git is unavailable; cannot clone $Url"
        return
    }
    if (Test-Path (Join-Path $Path '.git')) {
        Write-LogInfo "$Path already cloned; pulling updates"
        git -C $Path pull --ff-only
        if ($LASTEXITCODE -ne 0) { Write-LogWarn "git pull failed in $Path (fix repo manually)" }
    } elseif ((Test-Path $Path) -and (Get-ChildItem -Force $Path | Select-Object -First 1)) {
        Write-LogError "$Path exists, is non-empty, and is not a git repository - remove or rename it, then re-run"
    } else {
        Write-LogInfo "Cloning $Url to $Path"
        git clone $Url $Path
        if ($LASTEXITCODE -ne 0) { Write-LogError "git clone $Url failed" }
    }
}

function Install-Extras {
    Install-Winutil
    Update-GitRepo $PowershellisfunUrl (Join-Path $ProjectsDir 'Powershellisfun')
}

# ---------------------------------------------------------------------------
# System
# ---------------------------------------------------------------------------

function Enable-HyperV {
    try {
        if (Test-Command Get-WindowsFeature) {
            $feature = Get-WindowsFeature -Name Hyper-V
            if ($feature.Installed) {
                Write-LogInfo "Hyper-V is already installed"
                return
            }
            Write-LogInfo "Installing Hyper-V"
            $result = Install-WindowsFeature -Name Hyper-V -IncludeManagementTools
            if ($result.RestartNeeded -eq 'Yes') {
                $script:RebootRequired = $true
            }
        } else {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
            if ($feature.State -eq 'Enabled') {
                Write-LogInfo "Hyper-V is already enabled"
                return
            }
            Write-LogInfo "Enabling Hyper-V"
            $result = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart
            if ($result.RestartNeeded) {
                $script:RebootRequired = $true
            }
        }
    } catch {
        Write-LogError "Hyper-V installation failed (nested virtualization disabled?): $_"
    }
}

function Set-SystemTweaks {
    Write-LogInfo "Enabling Developer Mode"
    Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowDevelopmentWithoutDevLicense' 1

    Write-LogInfo "Enabling long paths"
    Set-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1

    Write-LogInfo "Showing file extensions and hidden files in Explorer"
    $explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-RegistryValue $explorer 'HideFileExt' 0
    Set-RegistryValue $explorer 'Hidden' 1

    $projects = $ProjectsDir
    if (Test-Command Add-MpPreference) {
        try {
            $excluded = @((Get-MpPreference).ExclusionPath)
            if ($excluded -contains $projects) {
                Write-LogInfo "Defender exclusion for $projects already exists"
            } else {
                Write-LogInfo "Adding Defender exclusion for $projects"
                Add-MpPreference -ExclusionPath $projects
            }
        } catch {
            Write-LogWarn "Could not configure Defender exclusions: $_"
        }
    } else {
        Write-LogWarn "Windows Defender is not installed; skipping exclusions"
    }
}

# ---------------------------------------------------------------------------
# OpenSSH server
# ---------------------------------------------------------------------------

$SshDataDir = Join-Path $env:ProgramData 'ssh'
$SshdConfig = Join-Path $SshDataDir 'sshd_config'
$AdminKeys = Join-Path $SshDataDir 'administrators_authorized_keys'
$SshFirewallRule = 'yadm-ssh-allowed-hosts'

# Sets "Key Value" in the global section of sshd_config (before the first Match block)
function Set-SshdOption([string[]]$Lines, [string]$Key, [string]$Value) {
    $pattern = "^\s*#?\s*$Key\s+"
    $matchIndex = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*Match\s') { $matchIndex = $i; break }
    }
    $limit = if ($matchIndex -ge 0) { $matchIndex } else { $Lines.Count }

    for ($i = 0; $i -lt $limit; $i++) {
        if ($Lines[$i] -match $pattern) {
            $Lines[$i] = "$Key $Value"
            return , $Lines
        }
    }
    $before = if ($limit -gt 0) { $Lines[0..($limit - 1)] } else { @() }
    $after = if ($limit -lt $Lines.Count) { $Lines[$limit..($Lines.Count - 1)] } else { @() }
    return , (@($before) + "$Key $Value" + @($after))
}

function Enable-SshServer {
    $capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
    if ($capability.State -ne 'Installed') {
        Write-LogInfo "Installing OpenSSH server"
        Add-WindowsCapability -Online -Name $capability.Name | Out-Null
    } else {
        Write-LogInfo "OpenSSH server is already installed"
    }

    Set-Service -Name sshd -StartupType Automatic
    # First start generates host keys and the default sshd_config
    Start-Service sshd

    Write-LogInfo "Restricting SSH firewall access to: $($AllowedHosts -join ', ')"
    Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP', 'sshd' -ErrorAction SilentlyContinue |
        Disable-NetFirewallRule
    $rule = Get-NetFirewallRule -Name $SshFirewallRule -ErrorAction SilentlyContinue
    if ($rule) {
        $rule | Set-NetFirewallRule -RemoteAddress $AllowedHosts -Enabled True
    } else {
        New-NetFirewallRule -Name $SshFirewallRule -DisplayName 'SSH (trusted hosts)' `
            -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow `
            -RemoteAddress $AllowedHosts | Out-Null
    }

    Write-LogInfo "Setting Windows PowerShell as the default SSH shell"
    Set-RegistryValue 'HKLM:\SOFTWARE\OpenSSH' 'DefaultShell' `
        "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" 'String'

    if ($SshPublicKeyFile) {
        if (-not (Test-Path $SshPublicKeyFile)) {
            throw "SSH public key file not found: $SshPublicKeyFile"
        }
        $existing = if (Test-Path $AdminKeys) { @(Get-Content -Path $AdminKeys) } else { @() }
        foreach ($key in Get-Content -Path $SshPublicKeyFile) {
            $key = $key.Trim()
            if (-not $key -or $key.StartsWith('#')) { continue }
            if ($existing -contains $key) {
                Write-LogInfo "SSH key already authorized: $key"
            } else {
                Write-LogInfo "Authorizing SSH key: $key"
                Add-Content -Path $AdminKeys -Value $key -Encoding Ascii
            }
        }
    }

    $keyInstalled = (Test-Path $AdminKeys) -and @(Get-Content -Path $AdminKeys | Where-Object { $_.Trim() }).Count -gt 0
    if ($keyInstalled) {
        # sshd ignores the file unless only Administrators and SYSTEM can access it
        # (SIDs instead of names: group names are localized)
        icacls.exe $AdminKeys /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null
    }

    $lines = @(Get-Content -Path $SshdConfig)
    $lines = Set-SshdOption $lines 'PubkeyAuthentication' 'yes'
    if ($keyInstalled) {
        $lines = Set-SshdOption $lines 'PasswordAuthentication' 'no'
    } else {
        Write-LogWarn ("No SSH keys in $AdminKeys; password authentication left enabled to avoid lockout. " +
            "Run add-ssh-key.ps1 to authorize a key.")
    }
    # sshd cannot parse a UTF-8 BOM, which Windows PowerShell 5.1 would add
    Set-Content -Path $SshdConfig -Value $lines -Encoding Ascii

    Restart-Service sshd
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Initialize-ProjectsDir
if (-not $SkipApps) {
    Install-Apps
    Install-Extras
}
if (-not $SkipSystem) {
    Enable-HyperV
    Set-SystemTweaks
}
if (-not $SkipSsh) { Enable-SshServer }

Write-Host ''
if ($script:Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    $script:Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
if ($script:Failed.Count -gt 0) {
    Write-Host 'Failures:' -ForegroundColor Red
    $script:Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-LogInfo 'Done without failures'
}

if ($script:RebootRequired) {
    $answer = Read-Host 'A reboot is required. Reboot now? [y/N]'
    if ($answer -match '^(y|yes)$') {
        Restart-Computer -Force
    }
}
