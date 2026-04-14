$OSVolume = Get-BitLockerVolume | Where-Object { $_.VolumeType -eq "OperatingSystem" }
$keyProtectors = $OSVolume.KeyProtector

$hasTpm      = $keyProtectors | Where-Object { $_.KeyProtectorType -eq 'Tpm' }
$hasRecovery = $keyProtectors | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
$hasTpmPin   = $keyProtectors | Where-Object { $_.KeyProtectorType -eq 'TpmPin' }

if ($hasRecovery -and $hasTpm) {
    Write-Output "True"
} else {
    Write-Output "False"
}