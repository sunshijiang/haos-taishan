<#
.SYNOPSIS
    Build the Home Assistant OS image for the LCKFB Taishan Pi on Windows.

.DESCRIPTION
    Drives WSL2 from PowerShell: installs the build dependencies once,
    then runs the Buildroot cross compilation. The image ends up in the
    output directory of the repository on the Windows drive.

    Run it from the repository root:

        powershell -ExecutionPolicy Bypass -File scripts\build-on-windows.ps1

.PARAMETER Jobs
    Packages compiled in parallel. 0 means one per core.

.PARAMETER Ref
    Build against a different upstream revision than the pinned one.

.PARAMETER SkipSetup
    Do not install the dependencies, they are already there.
#>
[CmdletBinding()]
param(
    [string]$Distribution = "",
    [string]$Jobs = "0",
    [string]$Ref = "",
    [switch]$SkipSetup
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
# /mnt/e/sun/TSP/haos-taishan, with a lower case drive letter, which is how
# WSL2 mounts it.
$drive = $RepoRoot.Substring(0, 1).ToLower()
$rest = $RepoRoot.Substring(2) -replace '\\', '/'
$ScriptDir = "/mnt/$drive$rest"

function Write-Step($Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Info($Text) {
    Write-Host "    $Text" -ForegroundColor Gray
}

# ---------------------------------------------------------------------
# 1. Check WSL
# ---------------------------------------------------------------------
Write-Step "Checking WSL2"

$wsl = Join-Path $env:SystemRoot "System32\wsl.exe"
if (-not (Test-Path $wsl)) {
    Write-Error "wsl.exe was not found. Install WSL2 with: wsl --install -d Ubuntu"
}

try {
    $null = & $wsl --status 2>&1
} catch {
    Write-Error "wsl.exe could not be started: $($_.Exception.Message)"
}

# Find the distribution to use.
$listOutput = & $wsl --list --quiet 2>&1 | Out-String
$distributions = @()
foreach ($line in ($listOutput -split "`n")) {
    $name = $line.Trim()
    if ($name -and $name -notmatch "^Windows Subsystem") {
        $distributions += $name
    }
}

if ($Distribution) {
    if ($distributions -notcontains $Distribution) {
        Write-Error "The distribution '$Distribution' was not found. Available: $($distributions -join ', ')"
    }
} elseif ($distributions.Count -gt 0) {
    $Distribution = $distributions[0]
    Write-Info "Using the distribution '$Distribution'"
} else {
    Write-Host ""
    Write-Host "No WSL distribution is installed yet." -ForegroundColor Yellow
    Write-Host "Install one and run this script again:" -ForegroundColor Yellow
    Write-Host "    wsl --install -d Ubuntu" -ForegroundColor White
    Write-Host ""
    exit 1
}

# ---------------------------------------------------------------------
# 2. Install the dependencies
# ---------------------------------------------------------------------
if (-not $SkipSetup) {
    Write-Step "Installing the build dependencies"
    Write-Info "This runs once. It asks for the sudo password of the WSL user."
    & $wsl -d $Distribution -- bash -c "cd '$ScriptDir' && bash scripts/wsl-setup.sh"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "The dependency installation failed."
    }
}

# ---------------------------------------------------------------------
# 3. Build
# ---------------------------------------------------------------------
Write-Step "Building the image"

$arguments = @("-d", $Distribution, "--", "bash", "-c")
$command = "cd '$ScriptDir' && bash scripts/wsl-build.sh"
if ($Jobs -ne "0") { $command += " --jobs $Jobs" }
if ($Ref) { $command += " --ref '$Ref'" }
$arguments += $command

Write-Info "This takes a few hours. The log is in ~haos-taishan-build/build.log"
Write-Info "Follow it with: wsl -d $Distribution -- tail -f ~/haos-taishan-build/build.log"
Write-Host ""

& $wsl @arguments
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "The build failed." -ForegroundColor Red
    Write-Host "The log is in the WSL filesystem: ~/haos-taishan-build/build.log" -ForegroundColor Gray
    exit 1
}

Write-Step "Done"
Write-Host "The image is in $RepoRoot\output\images\" -ForegroundColor Green
Get-ChildItem "$RepoRoot\output\images" -ErrorAction SilentlyContinue |
    Select-Object Name, @{Name="Size";Expression={ "{0:N1} MB" -f ($_.Length / 1MB) }} |
    Format-Table -AutoSize
