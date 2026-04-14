$app = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Systems Management Agent*" }

if ($app) {
    Write-Output "Detected: $($app.Name) - $($app.IdentifyingNumber)"
    Exit 1
} else {
    Write-Output "Not Detected"
    Exit 0
}