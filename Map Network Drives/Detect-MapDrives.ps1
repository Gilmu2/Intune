# Define required drives and paths
$Drives = @{
    "O" = "\\XXX\private_builds"
    "X" = "\\XXX\nt-dev"
    "Y" = "\\XXX\ckp"
    "Z" = "\\XXX\all_users"
}

$allMapped = $true

foreach ($DriveLetter in $Drives.Keys) {
    $mapped = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
    if (-not $mapped) {
        $allMapped = $false
        break
    }
}

if ($allMapped) {
    exit 0  # compliant
}
else {
    exit 1  # needs remediation
}