Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.InteropServices

# Define minimum and maximum PIN length
$minLength = 6
$maxLength = 20

# Define log path
$LogFile = "C:\Windows\TEMP\BitLockerEncryption_TpmPin_GUI.log"

# Delete existing log file if it exists
If (Test-Path $LogFile) { Remove-Item $LogFile -Force -ErrorAction SilentlyContinue -Confirm:$false }

# Function to write log entries with timestamp
function Write-Log {
    param ([string]$message)
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogFile -Value "$timestamp`t $message"
    } catch {
        Write-Host "Logging failed: $_" -ForegroundColor Red
    }
}

# Function to validate PIN complexity
function Is-ComplexPin {
    param ([string]$pin)
    return $pin -match '\d' -and $pin -match '[^a-zA-Z0-9]'
}

# GUI function to securely prompt user for PIN and return SecureString
function Get-ValidPinForm {
    do {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Enter BitLocker PIN"
        $form.Size = New-Object System.Drawing.Size(550, 200)
        $form.StartPosition = "CenterScreen"
        $form.TopMost = $true
        $form.MinimizeBox = $false
        $form.MaximizeBox = $false

        # Icon
        $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
        $iconPath = Join-Path -Path $scriptRoot -ChildPath "icon.ico"
        if (Test-Path $iconPath) { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath) }

        $label = New-Object System.Windows.Forms.Label
        $label.Text = "Enter a PIN code with at least one number,`none special character and be $minLength–$maxLength characters long."
        $label.AutoSize = $true
        $label.Location = New-Object System.Drawing.Point(20, 20)
        $form.Controls.Add($label)

        $textbox = New-Object System.Windows.Forms.TextBox
        $textbox.Location = New-Object System.Drawing.Point(20, 70)
        $textbox.Width = 300
        $textbox.UseSystemPasswordChar = $true
        $form.Controls.Add($textbox)

        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = "OK"
        $okButton.Location = New-Object System.Drawing.Point(80, 100)
        $okButton.Add_Click({
            $form.Tag = $textbox.Text
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        })
        $form.Controls.Add($okButton)

        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = "Cancel"
        $cancelButton.Location = New-Object System.Drawing.Point(180, 100)
        $cancelButton.Add_Click({
            $form.Tag = $null
            $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $form.Close()
        })
        $form.Controls.Add($cancelButton)

        # Add 15-minute timeout
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 900000 # 15 minutes in milliseconds
        $timer.Add_Tick({
            $timer.Stop()
            Write-Log "PIN entry form timed out after 15 minutes."
            Write-Host "PIN entry form timed out after 15 minutes." -ForegroundColor Yellow
            $form.Tag = $null
            $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $form.Close()
        })
        $timer.Start()

        $dialogResult = $form.ShowDialog()
        $form.Dispose()
        $timer.Dispose()

        $plainPin = $form.Tag

        if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK -or [string]::IsNullOrWhiteSpace($plainPin)) {
            Write-Log "User cancelled, timed out, or entered empty PIN."
            Write-Host "User cancelled, timed out, or entered empty PIN." -ForegroundColor Yellow
            throw "User cancelled or timed out during PIN entry."
        }

        $lengthValid = $plainPin.Length -ge $minLength -and $plainPin.Length -le $maxLength
        $complexValid = Is-ComplexPin -pin $plainPin

        if ($lengthValid -and $complexValid) {
            Write-Log "Valid PIN received."
            Write-Host "Valid PIN received." -ForegroundColor Yellow

            $securePin = ConvertTo-SecureString -String $plainPin -AsPlainText -Force

            # Clear the plaintext PIN variable from memory
            $ptr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($plainPin)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr)
            $plainPin = $null

            return $securePin
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("Invalid PIN. It must contain numbers, one special character and be $minLength–$maxLength characters long.", "Invalid PIN", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            Write-Log "Invalid PIN entered."
            Write-Host "Invalid PIN entered." -ForegroundColor Yellow
        }


    } while ($true)
}

# Main logic
try {
    Write-Log "===== Script started ====="

    Write-Log "Checking BitLocker volume info..."
    $OSVolume = Get-BitLockerVolume | Where-Object { $_.VolumeType -eq "OperatingSystem" }
    if (-not $OSVolume) {
        throw "No OS volume with BitLocker found."
    }

    $keyProtectors = $OSVolume.KeyProtector
    $volumeStatus = $OSVolume.VolumeStatus
    $MountPoint = $OSVolume.MountPoint

    Write-Log "Volume status: $volumeStatus"

    if ($volumeStatus -eq 'FullyEncrypted') {
        $hasTpm      = $keyProtectors | Where-Object { $_.KeyProtectorType -eq 'Tpm' }
        $hasRecovery = $keyProtectors | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
        $hasTpmPin   = $keyProtectors | Where-Object { $_.KeyProtectorType -eq 'TpmPin' }

        if ($hasRecovery -and $hasTpm -and -not $hasTpmPin) {
            Write-Log "TPM and RecoveryPassword found. TPM+PIN not found."
            Write-Host "TPM and RecoveryPassword found. TPM+PIN not found." -ForegroundColor Yellow

            $pin = Get-ValidPinForm

            if ($pin -is [System.Array]) {
                Write-Log "PIN is an array, selecting first SecureString element."
                Write-Host "PIN is an array, selecting first SecureString element." -ForegroundColor Yellow
                $pin = $pin | Where-Object { $_ -is [System.Security.SecureString] } | Select-Object -First 1
            }

            if ($pin -isnot [System.Security.SecureString]) {
                Write-Log "Warning: PIN is not a SecureString. Attempting to continue anyway."
                Write-Host "Warning: PIN is not a SecureString. Attempting to continue anyway." -ForegroundColor Yellow
            }

            Write-Log "PIN type before adding protector: $($pin.GetType().FullName)"

            Add-BitLockerKeyProtector -MountPoint $MountPoint -Pin $pin -TPMandPinProtector -Verbose
            Write-Log "TPM+PIN protector added successfully."
            Write-Host "TPM+PIN protector added successfully." -ForegroundColor Yellow
            [System.Windows.Forms.MessageBox]::Show("BitLocker TPM+PIN protector added successfully.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        elseif ($hasTpmPin) {
            Write-Log "TPM+PIN protector already exists."
            Write-Host "TPM+PIN protector already exists." -ForegroundColor Yellow
        }
        else {
            Write-Log "Protector requirements not met."
            Write-Host "TPM or RecoveryPassword protector not found. Cannot proceed." -ForegroundColor Yellow
            [System.Windows.Forms.MessageBox]::Show("TPM or RecoveryPassword protector not found. Cannot proceed.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
    else {
        Write-Log "Volume not fully encrypted: $volumeStatus"
        Write-Host "Volume not fully encrypted: $volumeStatus" -ForegroundColor Yellow
    }

    Write-Log "===== Script completed ====="
}
catch {
    Write-Log "Error occurred: $($_.Exception.Message)"
    Write-Host "Error occurred: $($_.Exception.Message)" -ForegroundColor Red

    Write-Log "===== Script completed ====="
}
