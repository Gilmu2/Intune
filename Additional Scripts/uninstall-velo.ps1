<#
.SYNOPSIS
    Uninstall Velociraptor Agent.
.DESCRIPTION
    Stops and removes the Velociraptor service, deletes all files and registry keys.
    Prepared for Intune Platform Script deployment - runs as SYSTEM.
.NOTES
    Exit 0 = Success
    Exit 1 = Failed with warnings
    Log file: C:\Windows\Temp\Velociraptor_Uninstall.log
    MSI log:  C:\Windows\Temp\Velociraptor_MSI.log
#>

$ErrorActionPreference = "SilentlyContinue"
$InstallPath = "C:\Program Files\Velociraptor"
$ServiceName = "velociraptor"
$LogFile     = "C:\Windows\Temp\Velociraptor_Uninstall.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $Message"
    Add-Content -Path $LogFile -Value $entry
    Write-Output $entry
}

# Clear previous log
if (Test-Path $LogFile) { Remove-Item $LogFile -Force }

Write-Log "=== Starting Velociraptor Uninstall ==="
Write-Log "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Machine: $env:COMPUTERNAME"

# Step 1 - Stop the service
Write-Log "Stopping Velociraptor service..."
$service = Get-Service -Name $ServiceName
if ($service) {
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 5
    Write-Log "Service stopped."
} else {
    Write-Log "Service not found, skipping stop."
}

# Step 2 - Kill any remaining processes
Write-Log "Killing any remaining Velociraptor processes..."
$procs = Get-Process -Name "Velociraptor"
if ($procs) {
    $procs | Stop-Process -Force
    Write-Log "Processes terminated."
} else {
    Write-Log "No running processes found."
}

# Step 3 - Uninstall via MSI (primary method)
Write-Log "Searching for MSI install via WMI..."
$app = Get-WmiObject -Class Win32_Product | 
    Where-Object { $_.Name -like "*Velociraptor*" -or $_.Vendor -like "*Velocidex*" }

if ($app) {
    Write-Log "Found MSI: $($app.Name) $($app.Version) [$($app.IdentifyingNumber)]"
    $guid   = $app.IdentifyingNumber
    $result = Start-Process "msiexec.exe" -ArgumentList "/x `"$guid`" /qn /norestart /l*v `"C:\Windows\Temp\Velociraptor_MSI.log`"" -Wait -PassThru
    Write-Log "MSI uninstall exit code: $($result.ExitCode)"
} else {
    Write-Log "No MSI found, falling back to manual removal..."
    $binary = Join-Path $InstallPath "Velociraptor.exe"
    $config = Join-Path $InstallPath "client.config.yaml"
    if (Test-Path $binary) {
        Start-Process -FilePath $binary -ArgumentList "--config `"$config`" service remove" -Wait -NoNewWindow
        Write-Log "Service removed via binary."
    } else {
        Start-Process "sc.exe" -ArgumentList "delete $ServiceName" -Wait -NoNewWindow
        Write-Log "Service removed via sc.exe."
    }
}

Start-Sleep -Seconds 5

# Step 4 - Delete installation directory
Write-Log "Deleting installation directory..."
if (Test-Path $InstallPath) {
    Remove-Item -Path $InstallPath -Recurse -Force
    if (Test-Path $InstallPath) {
        Write-Log "WARNING: Could not fully delete $InstallPath"
    } else {
        Write-Log "Deleted: $InstallPath"
    }
} else {
    Write-Log "Install directory already gone."
}

# Step 5 - Registry cleanup
Write-Log "Cleaning up registry..."

# Static service/software keys
$regPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName",
    "HKLM:\SOFTWARE\Velociraptor",
    "HKLM:\SOFTWARE\WOW6432Node\Velociraptor"
)
foreach ($path in $regPaths) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force
        Write-Log "Removed: $path"
    }
}

# ARP entries - search by publisher to handle GUID-based keys
$arpBases = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
foreach ($basePath in $arpBases) {
    if (Test-Path $basePath) {
        Get-ChildItem -Path $basePath | ForEach-Object {
            $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($props.Publisher -like "*Velocidex*" -or $props.DisplayName -like "*Velociraptor*") {
                Remove-Item -Path $_.PSPath -Recurse -Force
                Write-Log "Removed ARP entry: $($props.DisplayName) [$($_.PSPath)]"
            }
        }
    }
}

# Step 6 - Verify and report
Write-Log "Verifying removal..."
$serviceStillExists = Get-Service -Name $ServiceName
$filesStillExist    = Test-Path $InstallPath
$msiStillExists     = Get-WmiObject -Class Win32_Product | 
                        Where-Object { $_.Name -like "*Velociraptor*" -or $_.Vendor -like "*Velocidex*" }

if (-not $serviceStillExists -and -not $filesStillExist -and -not $msiStillExists) {
    Write-Log "=== Velociraptor successfully uninstalled ==="
    Write-Output "SUCCESS: Velociraptor removed from $env:COMPUTERNAME"
    exit 0
} else {
    if ($serviceStillExists) { Write-Log "WARNING: Service still exists!" }
    if ($filesStillExist)    { Write-Log "WARNING: Files still exist at $InstallPath" }
    if ($msiStillExists)     { Write-Log "WARNING: MSI entry still found in WMI!" }
    Write-Log "=== Uninstall completed with warnings ==="
    Write-Output "FAILED: Velociraptor not fully removed from $env:COMPUTERNAME - check C:\Windows\Temp\Velociraptor_Uninstall.log"
    exit 1
}
