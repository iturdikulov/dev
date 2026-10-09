#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Interactively authorize an SSH public key (e.g. volga's, from a USB stick)
    and disable SSH password authentication.

.DESCRIPTION
    Walks through: generating the key on the client, picking the .pub file
    (removable drives are scanned) or pasting it, verifying the fingerprint.
    The key is then applied by setup.ps1 -SkipApps -SkipSystem, which also
    restricts the firewall and turns off password logins.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\add-ssh-key.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SetupScript = Join-Path $PSScriptRoot 'setup.ps1'
$SshKeygen = "$env:SystemRoot\System32\OpenSSH\ssh-keygen.exe"
$KeyPattern = '^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp\d+|sk-\S+)\s+[A-Za-z0-9+/]+=*(\s.*)?$'

function Write-Step([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Hint([string]$Message) { Write-Host "    $Message" -ForegroundColor Gray }

function Read-YesNo([string]$Question, [bool]$Default = $true) {
    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$Question $suffix"
    if (-not $answer) { return $Default }
    return $answer -match '^(y|yes)$'
}

function Get-RemovablePubFiles {
    $drives = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter }
    foreach ($drive in $drives) {
        Get-ChildItem -Path "$($drive.DriveLetter):\" -Filter '*.pub' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue
    }
}

function Get-ValidKeys([string[]]$Lines) {
    @($Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match $KeyPattern })
}

if (-not (Test-Path $SetupScript)) {
    throw "setup.ps1 not found next to this script ($SetupScript)"
}

Write-Host 'Authorize an SSH key for this machine' -ForegroundColor Green

Write-Step 'Step 1. On the client (volga), create a key if you have none and copy it to a USB stick:'
Write-Hint 'ssh-keygen -t ed25519 -C "inom@volga"'
Write-Hint 'cp ~/.ssh/id_ed25519.pub /media/$USER/<usb>/'
Write-Hint 'ssh-keygen -lf ~/.ssh/id_ed25519.pub   # fingerprint, to compare in step 3'
Write-Hint 'Copy only the .pub file - never the private key.'
Read-Host "`nInsert the USB stick and press Enter" | Out-Null

Write-Step 'Step 2. Choose the public key'
$keys = @()
while ($keys.Count -eq 0) {
    $candidates = @(Get-RemovablePubFiles)
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $candidates[$i].FullName)
    }
    Write-Host '  [p] paste the key text'
    Write-Host '  [m] enter a file path manually'
    Write-Host '  [r] rescan drives'
    Write-Host '  [q] quit'
    $choice = Read-Host 'Choice'

    $lines = @()
    switch -Regex ($choice) {
        '^q$' { Write-Host 'Aborted.'; exit 1 }
        '^r$' { } # loop again, rescanning drives
        '^p$' { $lines = @(Read-Host 'Paste the key (one line, starts with ssh-ed25519 ...)') }
        '^m$' {
            $path = (Read-Host 'Path to .pub file').Trim('"', ' ')
            if (Test-Path $path -PathType Leaf) {
                $lines = @(Get-Content -Path $path)
            } else {
                Write-Host "File not found: $path" -ForegroundColor Red
            }
        }
        '^\d+$' {
            $index = [int]$choice - 1
            if ($index -ge 0 -and $index -lt $candidates.Count) {
                $lines = @(Get-Content -Path $candidates[$index].FullName)
            } else {
                Write-Host 'No such item.' -ForegroundColor Red
            }
        }
        default { Write-Host 'Unknown choice.' -ForegroundColor Red }
    }

    if ($lines.Count -gt 0) {
        $keys = @(Get-ValidKeys $lines)
        if ($keys.Count -eq 0) {
            Write-Host 'No valid public key found (is that the private key?). Try again.' -ForegroundColor Red
        }
    }
}

$keyFile = [IO.Path]::GetTempFileName()
try {
    Set-Content -Path $keyFile -Value $keys -Encoding Ascii

    Write-Step 'Step 3. Verify the fingerprint matches the client (ssh-keygen -lf on volga):'
    if (Test-Path $SshKeygen) {
        & $SshKeygen -lf $keyFile | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    } else {
        $keys | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    }
    if (-not (Read-YesNo 'Fingerprint matches, authorize this key and disable password logins?')) {
        Write-Host 'Aborted, nothing changed.'
        exit 1
    }

    Write-Step 'Step 4. Applying SSH configuration (setup.ps1 -SkipApps -SkipSystem)'
    & $SetupScript -SkipApps -SkipSystem -SshPublicKeyFile $keyFile
} finally {
    Remove-Item -Path $keyFile -Force -ErrorAction SilentlyContinue
}

Write-Step 'Step 5. Test from the client:'
$addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
    Select-Object -ExpandProperty IPAddress
foreach ($address in $addresses) {
    Write-Hint "ssh $env:USERNAME@$address"
}
Write-Hint "ssh -o PubkeyAuthentication=no $env:USERNAME@<ip>   # must fail: Permission denied"
Write-Hint 'Keep this session open until the key login works.'
