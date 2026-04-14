# Install module if not installed
# Install-Module AzureAD -Scope CurrentUser

Import-Module AzureAD

# Connect to Azure AD
Connect-AzureAD

# Target group
$GroupName = "SG-Intune_Endpoint_Users"

# Output CSV
$CsvPath = "C:\Temp\SG-Intune_Endpoint_Users_Members.csv"

# Recursive function to get members
function Get-AzureADGroupMembersRecursive {
    param (
        [string]$GroupId
    )

    # Get direct members
    $members = Get-AzureADGroupMember -ObjectId $GroupId

    foreach ($member in $members) {
        if ($member.ObjectType -eq "User") {
            # Output user
            [PSCustomObject]@{
                DisplayName = $member.DisplayName
                UserPrincipalName = $member.UserPrincipalName
                ObjectId = $member.ObjectId
            }
        }
        elseif ($member.ObjectType -eq "Group") {
            # Recursive call for nested groups
            Get-AzureADGroupMembersRecursive -GroupId $member.ObjectId
        }
    }
}

# Get the group ID
$Group = Get-AzureADGroup -Filter "DisplayName eq '$GroupName'"

if ($null -eq $Group) {
    Write-Error "Group '$GroupName' not found in Azure AD"
    return
}

# Get all members recursively
$AllMembers = Get-AzureADGroupMembersRecursive -GroupId $Group.ObjectId

# Remove duplicates
$AllMembers = $AllMembers | Sort-Object UserPrincipalName -Unique

# Export to CSV
$AllMembers | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

Write-Host "Export completed. CSV saved to $CsvPath"
