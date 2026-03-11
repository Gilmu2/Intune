# Get the BitLocker volume marked as the Operating System volume
$OSVolume = Get-BitLockerVolume | Where-Object VolumeType -eq "OperatingSystem"

# Get all key protectors associated with the OS volume
$keyProtectors = $OSVolume.KeyProtector

# Check for presence of different key protector types
$hasRecovery = $keyProtectors | Where-Object KeyProtectorType -eq 'RecoveryPassword'
$hasTpmPin   = $keyProtectors | Where-Object KeyProtectorType -eq 'TpmPin'
$hasTpm      = $keyProtectors | Where-Object KeyProtectorType -eq 'Tpm'

# Prepare status strings
$hasRecoveryStatus = if ($hasRecovery) { "True" } else { "False" }
$hasTpmPinStatus   = if ($hasTpmPin) { "True" } else { "False" }

# Return JSON-formatted output
$hash = @{ "RecoveryPassword" = "$hasRecoveryStatus"; "TpmPin" = "$hasTpmPinStatus" }
return $hash | ConvertTo-Json -Compress