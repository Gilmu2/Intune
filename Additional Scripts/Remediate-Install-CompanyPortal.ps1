# Remediate-Install-CompanyPortal.ps1
$ErrorActionPreference = "Stop"

$LogDir = "C:\ProgramData\CompanyPortalRemediation"
$LogFile = Join-Path $LogDir "Remediate-CompanyPortal.log"
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

Write-Log "==== Remediation started: Install Company Portal via WinGet ===="

# If already installed, exit success
try {
    $pkg = Get-AppxPackage -Name "Microsoft.CompanyPortal" -ErrorAction SilentlyContinue
    if ($pkg) {
        Write-Log "Company Portal already installed. Version: $($pkg.Version)"
        exit 0
    }
} catch {}

# Locate winget
$winget = $null

# Try standard command resolution
$cmd = Get-Command "winget.exe" -ErrorAction SilentlyContinue
if ($cmd) { $winget = $cmd.Source }

# Try WindowsApps pattern (works often when App Installer is present)
if (-not $winget) {
    $wa = Join-Path $env:ProgramFiles "WindowsApps"
    $candidates = Get-ChildItem -Path $wa -Filter "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending

    foreach ($c in $candidates) {
        $p = Join-Path $c.FullName "winget.exe"
        if (Test-Path $p) { $winget = $p; break }
    }
}

if (-not $winget) {
    Write-Log "WinGet not found. App Installer may be missing/outdated or blocked."
    Write-Log "Cannot proceed with winget. Exiting with failure."
    exit 1
}

Write-Log "Using WinGet: $winget"

# Install Company Portal
# Store ID: 9WZDNCRFJ3PZ
$args = @(
    "install",
    "9WZDNCRFJ3PZ",
    "--source", "msstore",
    "--accept-source-agreements",
    "--accept-package-agreements",
    "--silent"
)

Write-Log "Executing: $winget $($args -join ' ')"

try {
    $proc = Start-Process -FilePath $winget -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    Write-Log "WinGet exit code: $($proc.ExitCode)"
} catch {
    Write-Log "WinGet execution failed: $_"
    exit 1
}

Start-Sleep -Seconds 10

# Verify install
$pkg = Get-AppxPackage -Name "Microsoft.CompanyPortal" -ErrorAction SilentlyContinue
if ($pkg) {
    Write-Log "SUCCESS: Company Portal installed. Version: $($pkg.Version)"
    exit 0
}

Write-Log "FAILED: Company Portal not detected after winget install."
exit 1