param([ValidatePattern('^COM[0-9]+$')][string]$Port = 'COM7')
$ErrorActionPreference = 'Stop'
$taskRepo = Split-Path -Parent $PSScriptRoot
$taskCli = Join-Path $env:USERPROFILE 'AppData/Local/Programs/Arduino IDE/resources/app/lib/backend/resources/arduino-cli.exe'
if (-not (Test-Path -LiteralPath $taskCli)) { throw 'Arduino IDE CLI not found. Install Arduino IDE or ask for the path to be updated.' }
$taskConfig = Join-Path $taskRepo '.tool-state/arduino/arduino-cli.yaml'
$taskLibrary = Join-Path $taskRepo '.tool-state/arduino/libraries/hd44780-1.3.2'
if (-not (Test-Path -LiteralPath $taskConfig)) { throw 'Local Arduino configuration is missing.' }
if (-not (Test-Path -LiteralPath $taskLibrary)) { throw 'The hd44780 LCD library is missing.' }
$taskSketch = Join-Path $taskRepo 'hardware/krishi_field_demo'
$taskSource = Get-Content -LiteralPath (Join-Path $taskSketch 'krishi_field_demo.ino') -Raw
$taskBuild = Join-Path $taskRepo ('.tool-state/arduino/build-display-' + [guid]::NewGuid().ToString('N'))
Write-Host 'Close Arduino IDE Serial Monitor and any other program using the board.'
Write-Host 'Expected LCD: relative moisture 0-100% and DEMO temperature in degrees Celsius.'
Write-Host 'Provisional moisture references: dry AIR 525 and wet SOIL estimated 264 (midpoint of reported 255-272).'
Write-Host 'These are relative moisture percentages, not validated soil water content. Temperature remains simulated.'
if ($taskSource -notmatch 'const int DRY_RAW = 525;' -or $taskSource -notmatch 'const int WET_RAW = 264;') {
    throw 'Calibration has changed. Review this updater before flashing.'
}
& $taskCli compile --fqbn arduino:avr:uno --config-file $taskConfig --build-path $taskBuild --library $taskLibrary $taskSketch
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed. The board was not flashed.' }
$taskHex = Join-Path $taskBuild 'krishi_field_demo.ino.hex'
if (-not (Test-Path -LiteralPath $taskHex)) { throw 'Compiled sketch was not found. The board was not flashed.' }
$taskTools = Join-Path $env:USERPROFILE 'AppData/Local/Arduino15/packages/arduino/tools/avrdude'
$taskAvrdudeRoot = Get-ChildItem -LiteralPath $taskTools -Directory | Sort-Object Name -Descending | Select-Object -First 1
if (-not $taskAvrdudeRoot) { throw 'avrdude is missing; backup cannot be made. No firmware changed.' }
$taskAvrdude = Join-Path $taskAvrdudeRoot.FullName 'bin/avrdude.exe'
$taskAvrdudeConfig = Join-Path $taskAvrdudeRoot.FullName 'etc/avrdude.conf'
$taskBackupDir = Join-Path $taskRepo '.tool-state/hardware-backups'
New-Item -Path $taskBackupDir -ItemType Directory -Force | Out-Null
$taskBackup = Join-Path $taskBackupDir ('before-display-update-' + [guid]::NewGuid().ToString('N') + '.hex')
Write-Host 'Reading a backup of the existing firmware before upload...'
& $taskAvrdude "-C$taskAvrdudeConfig" -p atmega328p -c arduino "-P$Port" -b 115200 -D '-U' "flash:r:${taskBackup}:i"
if ($LASTEXITCODE -ne 0) { throw 'Backup failed. No new firmware was uploaded. Close other Serial Monitors and check the cable/port.' }
Write-Host 'Uploading prepared firmware (flash verification is enabled)...'
& $taskCli upload --verify --fqbn arduino:avr:uno --port $Port --config-file $taskConfig --input-dir $taskBuild $taskSketch
if ($LASTEXITCODE -ne 0) { throw "Upload failed. Existing firmware backup is saved at $taskBackup" }
Write-Host 'Firmware uploaded and verified. Reading startup and sensor output...'
$taskSerial = [System.IO.Ports.SerialPort]::new($Port,9600,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$taskSerial.ReadTimeout = 1200
$taskSerial.DtrEnable = $true
$taskLcdReady = $false
$taskReportSeen = $false
try {
    $taskSerial.Open()
    $taskDeadline = [DateTime]::UtcNow.AddSeconds(12)
    while ([DateTime]::UtcNow -lt $taskDeadline) {
        try {
            $taskLine = $taskSerial.ReadLine().Trim()
            if ($taskLine) {
                Write-Host $taskLine
                if ($taskLine -eq 'LCD ready.') { $taskLcdReady = $true }
                if ($taskLine.StartsWith('{')) {
                    try {
                        $taskReading = $taskLine | ConvertFrom-Json
                        if ($taskReading.moisture -ge 0 -and $taskReading.moisture -le 100 -and $taskReading.temperatureSource -eq 'simulated') { $taskReportSeen = $true }
                    } catch { }
                }
                if ($taskLcdReady -and $taskReportSeen) { break }
            }
        } catch [System.TimeoutException] { }
    }
} catch { Write-Warning ('Firmware uploaded, but serial verification could not finish: ' + $_.Exception.Message) }
finally { if ($taskSerial.IsOpen) { $taskSerial.Close() }; $taskSerial.Dispose() }
if ($taskLcdReady -and $taskReportSeen) {
    Write-Host 'CHECK PASSED: firmware reports LCD ready and valid relative moisture / simulated temperature output.'
} else {
    Write-Warning 'Firmware uploaded, but LCD/data startup verification is incomplete. Share the output above.'
}
Write-Host 'On the actual LCD, confirm Rel moist: ...% and DEMO ... degrees C.'
Write-Host 'Copy those numeric readings into the same existing Krishi Team visit form.'
