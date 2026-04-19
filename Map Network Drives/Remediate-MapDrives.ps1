# Define drives and share paths
$Drives = @{
    "O" = "\\XXX\private_builds"
    "X" = "\\XXX\nt-dev"
    "Y" = "\\XXX\ckp"
    "Z" = "\\XXX\all_users"
}

foreach ($DriveLetter in $Drives.Keys) {
    $SharePath = $Drives[$DriveLetter]

    # Remove existing mapping if exists
    if (Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue) {
        Remove-PSDrive -Name $DriveLetter -Force
    }

    # Create the mapped drive
    New-PSDrive -Name $DriveLetter -PSProvider FileSystem -Root $SharePath -Persist
    Write-Host "Mapped drive $DriveLetter to $SharePath"
}
