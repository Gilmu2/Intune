<#
.SYNOPSIS
    Uninstall (if present) and cleanup GYTPOLClient. Does NOT reinstall.

.DESCRIPTION
    - If GYTPOLClient is not installed, reports success and exits.
    - Kills any running GYTPOL processes before attempting uninstall.
    - If installed, attempts uninstall via registry UninstallString / QuietUninstallString.
    - Uninstall uses a 120-second timeout.
    - Validates uninstall by ExitCode and registry check.
    - If uninstall fails, performs registry + file + task cleanup (SAFE: no HKCR:\Installer\Products deletion).
    - Verifies GYTPOL is fully removed (not reinstalled).
#>

# Require elevation
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script as Administrator." -ForegroundColor Red
    exit 1
}

function Stop-GYTPOLProcesses {
    Write-Host "Stopping any running GYTPOL processes..." -ForegroundColor Blue

    $processNames = @("GYTPOLClient", "GYTPOL", "GytpolClientFW4_6_2")

    foreach ($name in $processNames) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($procs) {
            foreach ($proc in $procs) {
                try {
                    $proc.Kill()
                    $proc.WaitForExit(5000) | Out-Null
                    Write-Host "Stopped process: $name (PID $($proc.Id))" -ForegroundColor Green
                } catch {
                    Write-Host "Could not stop process: $name (PID $($proc.Id)). $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }

    # Also stop any GYTPOL Windows services
    $services = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*GYTPOL*" -or $_.ServiceName -like "*GYTPOL*" }
    foreach ($svc in $services) {
        try {
            if ($svc.Status -ne 'Stopped') {
                Stop-Service -Name $svc.ServiceName -Force -ErrorAction Stop
                Write-Host "Stopped service: $($svc.ServiceName)" -ForegroundColor Green
            }
        } catch {
            Write-Host "Could not stop service: $($svc.ServiceName). $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Start-Sleep -Seconds 2
}

function Remove-RegistryKey {
    [CmdletBinding()]
    param ([string]$Path)

    if (Test-Path $Path) {
        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Host "Removed registry key: $Path" -ForegroundColor Green
        } catch {
            Write-Host "Error removing registry key: $Path. $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

function Start-ProcessWithTimeout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter()] [string]$ArgumentList,
        [int]$TimeoutSeconds = 5
    )

    $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -ErrorAction Stop
    $exited = $p.WaitForExit($TimeoutSeconds * 1000)

    if (-not $exited) {
        try { $p.Kill() | Out-Null } catch {}
        return [pscustomobject]@{ TimedOut = $true; ExitCode = $null; Process = $p }
    }

    return [pscustomobject]@{ TimedOut = $false; ExitCode = $p.ExitCode; Process = $p }
}

function Get-GYTPOLUninstallEntry {
    $is64OS = [Environment]::Is64BitOperatingSystem
    $targetName = if ($is64OS) { "GYTPOLClient x64" } else { "GYTPOLClient x86" }

    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($path in $uninstallPaths) {
        if (Test-Path $path) {
            foreach ($k in (Get-ChildItem $path -ErrorAction SilentlyContinue)) {
                $props = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { continue }

                $nameToCheck = $null
                if ($props.PSObject.Properties.Name -contains "ProductName" -and $props.ProductName) {
                    $nameToCheck = [string]$props.ProductName
                } else {
                    $nameToCheck = [string]$props.DisplayName
                }

                if ($nameToCheck -and $nameToCheck.Trim().Equals($targetName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $props
                }
            }
        }
    }
    return $null
}

function Try-UninstallGYTPOL {
    $entry = Get-GYTPOLUninstallEntry
    if ($null -eq $entry) {
        Write-Host "No existing GYTPOL installation found. Nothing to uninstall." -ForegroundColor Yellow
        return $null  # special signal: not installed
    }

    $display = if ($entry.PSObject.Properties.Name -contains "DisplayName") { $entry.DisplayName } else { "(unknown name)" }
    Write-Host "Found uninstall entry: $display" -ForegroundColor Yellow

    $raw = $entry.QuietUninstallString
    if (-not $raw) { $raw = $entry.UninstallString }

    if (-not $raw) {
        Write-Host "UninstallString and QuietUninstallString not found for entry." -ForegroundColor Red
        return $false
    }

    $processExitCode = $null

    if ($raw -match '\{[0-9A-Fa-f-]{36}\}') {
        $guid = $Matches[0]
        Write-Host "Attempting uninstall via product code: $guid (timeout 120s)" -ForegroundColor Blue

        try {
            $result = Start-ProcessWithTimeout -FilePath "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -TimeoutSeconds 120
            if ($result.TimedOut) {
                Write-Host "Uninstall timed out after 120 seconds." -ForegroundColor Red
                return $false
            }
            $processExitCode = $result.ExitCode
            Write-Host "Uninstall process exited with code $processExitCode" -ForegroundColor Cyan
        } catch {
            Write-Host "Error during uninstall: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    } else {
        $cmdToRun = $raw
        if ($cmdToRun -match '(?i)msiexec(\.exe)?' -and $cmdToRun -notmatch '(?i)\s/qn(\s|$)') {
            $cmdToRun = "$cmdToRun /qn /norestart"
        }

        Write-Host "Attempting uninstall using raw command (timeout 120s): $cmdToRun" -ForegroundColor Blue

        try {
            $result = Start-ProcessWithTimeout -FilePath "cmd.exe" -ArgumentList "/c `"$cmdToRun`"" -TimeoutSeconds 120
            if ($result.TimedOut) {
                Write-Host "Uninstall timed out after 120 seconds." -ForegroundColor Red
                return $false
            }
            $processExitCode = $result.ExitCode
            Write-Host "Uninstall process exited with code $processExitCode" -ForegroundColor Cyan
        } catch {
            Write-Host "Error during uninstall: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }

    if ($processExitCode -eq 0 -or $processExitCode -eq 3010) {
        Start-Sleep -Seconds 3
        $verify = Get-GYTPOLUninstallEntry
        if ($null -eq $verify) {
            Write-Host "Uninstall verified: GYTPOL entry is gone." -ForegroundColor Green
            return $true
        } else {
            Write-Host "Uninstall returned success but entry still exists." -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "Uninstall failed (ExitCode=$processExitCode)." -ForegroundColor Red
        return $false
    }
}

function Cleanup-GYTPOL {
    Write-Host "Running fallback cleanup..." -ForegroundColor Blue

    # SAFE cleanup only (no HKCR:\Installer\Products deletion)
    Remove-RegistryKey -Path "HKLM:\SOFTWARE\GYTPOL"

    $tracingRoot = "HKLM:\SOFTWARE\Microsoft\Tracing"
    if (Test-Path $tracingRoot) {
        Get-ChildItem $tracingRoot -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -like "GYTPOLClient*" } |
            ForEach-Object { Remove-RegistryKey -Path $_.PSPath }
    }

    try {
        Remove-Item -Path "C:\Program Files\WindowsPowerShell\Modules\GYTPOL" -Recurse -Force -ErrorAction Stop
        Write-Host "Removed folder: C:\Program Files\WindowsPowerShell\Modules\GYTPOL" -ForegroundColor Green
    } catch {
        Write-Host "Could not remove folder (may not exist or access denied): C:\Program Files\WindowsPowerShell\Modules\GYTPOL. $($_.Exception.Message)" -ForegroundColor Yellow
    }

    try {
        $GYTPOLTasks = Get-ScheduledTask -TaskPath "\GYTPOL\" -ErrorAction SilentlyContinue
        if ($GYTPOLTasks) {
            $GYTPOLTasks | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "Removed all tasks under Task Scheduler path: \GYTPOL\" -ForegroundColor Green
        } else {
            Write-Host "No tasks found under Task Scheduler path: \GYTPOL\" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "No Task Scheduler tasks under \GYTPOL found or could not be removed. $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Remove root-level "GYTPOL Hourly" task (v3+, lives outside \GYTPOL\ folder)
    try {
        $hourlyTask = Get-ScheduledTask -TaskName "GYTPOL Hourly" -ErrorAction Stop
        $hourlyTask | Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop
        Write-Host "Removed scheduled task: GYTPOL Hourly" -ForegroundColor Green
    } catch {
        Write-Host "Scheduled task 'GYTPOL Hourly' not found or already removed." -ForegroundColor Yellow
    }

    Write-Host "Cleanup complete." -ForegroundColor Magenta
}

function Verify-GYTPOLUninstall {
    Write-Host "Verifying GYTPOL is fully removed..." -ForegroundColor Blue
    $allClean = $true

    # 1. Check uninstall registry entry is gone
    $entry = Get-GYTPOLUninstallEntry
    if ($null -ne $entry) {
        $display = if ($entry.PSObject.Properties.Name -contains "DisplayName") { $entry.DisplayName } else { "(unknown name)" }
        Write-Host "FAIL: GYTPOL uninstall entry still exists: $display" -ForegroundColor Red
        $allClean = $false
    } else {
        Write-Host "PASS: No GYTPOL uninstall entry found in registry." -ForegroundColor Green
    }

    # 2. Check GYTPOL registry key is gone
    $regPaths = @("HKLM:\SOFTWARE\GYTPOL", "HKLM:\SOFTWARE\WOW6432Node\GYTPOL")
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            Write-Host "FAIL: Registry key still exists: $rp" -ForegroundColor Red
            $allClean = $false
        } else {
            Write-Host "PASS: Registry key not present: $rp" -ForegroundColor Green
        }
    }

    # 3. Check GYTPOL folder is gone
    $folderPath = "C:\Program Files\WindowsPowerShell\Modules\GYTPOL"
    if (Test-Path $folderPath) {
        Write-Host "FAIL: GYTPOL folder still exists: $folderPath" -ForegroundColor Red
        $allClean = $false
    } else {
        Write-Host "PASS: GYTPOL folder not present: $folderPath" -ForegroundColor Green
    }

    # 4. Check scheduled tasks are gone
    $taskChecks = @(
        @{ Name = "GYTPOL Hourly"; Path = $null },
        @{ Name = "GYTPOLTask";    Path = "\GYTPOL\" },
        @{ Name = "GYTPOLTask hourly"; Path = "\GYTPOL\" },
        @{ Name = "GYTPOLClient"; Path = "\GYTPOL\" }
    )

    foreach ($t in $taskChecks) {
        try {
            $params = @{ TaskName = $t.Name; ErrorAction = "Stop" }
            if ($t.Path) { $params["TaskPath"] = $t.Path }
            Get-ScheduledTask @params | Out-Null
            $label = if ($t.Path) { "$($t.Path)$($t.Name)" } else { $t.Name }
            Write-Host "FAIL: Scheduled task still exists: $label" -ForegroundColor Red
            $allClean = $false
        } catch {
            $label = if ($t.Path) { "$($t.Path)$($t.Name)" } else { $t.Name }
            Write-Host "PASS: Scheduled task not present: $label" -ForegroundColor Green
        }
    }

    Write-Host ""
    if ($allClean) {
        Write-Host "=== Verification PASSED: GYTPOL is fully removed. ===" -ForegroundColor Green
    } else {
        Write-Host "=== Verification FAILED: Some GYTPOL remnants were detected (see above). ===" -ForegroundColor Red
    }
}

# === Main flow ===
Write-Host "=== GYTPOL Uninstall Script ===" -ForegroundColor Cyan

Stop-GYTPOLProcesses

$uninstallResult = Try-UninstallGYTPOL

if ($uninstallResult -eq $null) {
    Write-Host "GYTPOL was not installed. Proceeding to verify clean state." -ForegroundColor Cyan
    Cleanup-GYTPOL
} elseif (-not $uninstallResult) {
    Write-Host "Uninstall did not succeed cleanly. Running fallback cleanup..." -ForegroundColor Yellow
    Stop-GYTPOLProcesses
    Cleanup-GYTPOL
} else {
    Write-Host "Uninstall completed successfully. Running post-uninstall cleanup of leftover files..." -ForegroundColor Green
    Cleanup-GYTPOL
}

Verify-GYTPOLUninstall

Write-Host "=== Finished ===" -ForegroundColor Cyan
