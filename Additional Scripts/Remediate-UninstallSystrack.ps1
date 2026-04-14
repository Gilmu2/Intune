try {
    $apps = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Systems Management Agent*" }

    if (-not $apps) {
        Write-Output "Nothing to uninstall"
        Exit 0
    }

    foreach ($app in $apps) {
        Write-Output "Uninstalling: $($app.Name) - $($app.IdentifyingNumber)"
        $result = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $($app.IdentifyingNumber) /qn REBOOT=R" -Wait -PassThru

        if ($result.ExitCode -ne 0) {
            Write-Output "Failed to uninstall $($app.Name), exit code: $($result.ExitCode)"
            Exit 1
        }
    }

    Write-Output "All versions uninstalled successfully"
    Exit 0
} catch {
    Write-Output "Error: $_"
    Exit 1
}