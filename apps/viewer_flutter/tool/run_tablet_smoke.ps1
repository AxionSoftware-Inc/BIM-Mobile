param([string]$DeviceId = '')

$ErrorActionPreference = 'Stop'
$Flutter = 'C:\src\flutter\bin\flutter.bat'
$Adb = 'C:\Users\shaxz\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$GitBin = 'C:\Program Files\Git\cmd'
$env:Path = "$GitBin;$env:Path"

$attached = @(& $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\tdevice\s*$' })
if ($attached.Count -eq 0) {
    throw 'No Android device found. Connect a tablet, enable USB debugging, accept the RSA prompt, and retry.'
}
if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    $DeviceId = ($attached[0] -split '\s+')[0]
}

Write-Host "Running tablet gesture smoke test on $DeviceId"
& $Flutter test integration_test/tablet_stability_workflow_test.dart -d $DeviceId
