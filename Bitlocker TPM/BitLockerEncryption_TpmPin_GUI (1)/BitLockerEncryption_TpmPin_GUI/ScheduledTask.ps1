# Define log path
$LogFile = "C:\Windows\TEMP\ScheduledTask.log"

# Delete existing log file if it exists
If (Test-Path $LogFile) { Remove-Item $LogFile -Force -ErrorAction SilentlyContinue -Confirm:$false }

# Start logging to file
Start-Transcript -Path $LogFile -Force

$TaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>PC1NYHV0\LocalUser</Author>
    <URI>\BitLockerEncryption_TpmPin_GUI</URI>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <Repetition>
        <Interval>PT1H</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2025-01-01T12:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>"C:\Windows\Temp\BitLockerEncryption_TpmPin_GUI\Install.cmd"</Command>
    </Exec>
  </Actions>
</Task>
"@
 
# Save to temp file
$TempFile = "C:\Windows\TEMP\BitLockerEncryption_TpmPin_GUI.xml"
$TaskXml | Out-File -FilePath $TempFile -Encoding Unicode
 
# Register the task with the added description
Register-ScheduledTask -Xml (Get-Content $TempFile | Out-String) -TaskName "BitLockerEncryption_TpmPin_GUI" -Force -Verbose
 
# Cleanup
Remove-Item $TempFile

# Stop logging
Stop-Transcript