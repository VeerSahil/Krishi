param(
    [ValidateSet('farmer', 'team', 'both')]
    [string]$Audience = 'both',
    [string]$JdkHome,
    [string]$ApiBaseUrl,
    [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$mobileRoot = Join-Path $projectRoot 'mobile'
$previousJava = $env:JAVA_HOME
$previousPath = $env:PATH

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed with exit code $LASTEXITCODE" }
}

# Gradle 8.3 needs an older JDK than the Java 21 bundled with current Android Studio.
# Call Gradle directly so Flutter's global jdk-dir setting cannot replace JAVA_HOME.
if (-not $JdkHome) {
    $candidates = @($env:JAVA_HOME)
    $portableRoot = Join-Path $projectRoot '.tool-state/java'
    if (Test-Path -LiteralPath $portableRoot) {
        $candidates += @(Get-ChildItem -LiteralPath $portableRoot -Directory -Filter 'jdk-17*' | ForEach-Object FullName)
    }
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        $releaseFile = Join-Path $candidate 'release'
        if ((Test-Path -LiteralPath $releaseFile) -and
            ((Get-Content -LiteralPath $releaseFile -Raw) -match 'JAVA_VERSION="17\.')) {
            $JdkHome = $candidate
            break
        }
    }
}
if (-not $JdkHome -or -not (Test-Path -LiteralPath (Join-Path $JdkHome 'bin/java.exe'))) {
    throw 'Install JDK 17, then pass -JdkHome with its installation folder.'
}
$jdkRelease = Get-Content -LiteralPath (Join-Path $JdkHome 'release') -Raw
if ($jdkRelease -notmatch 'JAVA_VERSION="17\.') { throw 'Use JDK 17 for this Gradle wrapper.' }

$flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
$flutterRoot = Split-Path -Parent (Split-Path -Parent $flutterCommand)
$sdkPath = $env:ANDROID_SDK_ROOT
if (-not $sdkPath) { $sdkPath = $env:ANDROID_HOME }
if (-not $sdkPath) { $sdkPath = Join-Path $env:LOCALAPPDATA 'Android/sdk' }
if (-not (Test-Path -LiteralPath $sdkPath)) { throw 'Set ANDROID_SDK_ROOT to your Android SDK folder.' }

Push-Location $mobileRoot
try {
    $env:JAVA_HOME = (Resolve-Path -LiteralPath $JdkHome).Path
    $env:PATH = "$env:JAVA_HOME\bin;$previousPath"
    Invoke-Checked -Executable $flutterCommand -Arguments @('pub', 'get')
    if (-not $SkipChecks) {
        Invoke-Checked -Executable $flutterCommand -Arguments @('analyze')
        Invoke-Checked -Executable $flutterCommand -Arguments @('test')
    }
    $versionText = Get-Content -LiteralPath 'pubspec.yaml' -Raw
    if ($versionText -notmatch '(?m)^version:\s*([^+\s]+)\+(\d+)\s*$') {
        throw 'pubspec.yaml must contain a version such as 1.0.0+1.'
    }
    $versionName = $Matches[1]
    $versionCode = $Matches[2]
    # This is generated, Git-ignored, machine-specific configuration.
    @(
        'sdk.dir=' + $sdkPath.Replace('\', '/')
        'flutter.sdk=' + $flutterRoot.Replace('\', '/')
        'flutter.buildMode=release'
        'flutter.versionName=' + $versionName
        'flutter.versionCode=' + $versionCode
    ) | Set-Content -LiteralPath 'android/local.properties' -Encoding ASCII

    $dartDefines = $null
    if ($ApiBaseUrl) {
        $apiUri = $null
        if (-not [Uri]::TryCreate($ApiBaseUrl, [UriKind]::Absolute, [ref]$apiUri) -or
            $apiUri.Scheme -notin @('https', 'http')) {
            throw 'ApiBaseUrl must be an absolute HTTP or HTTPS URL.'
        }
        $defines = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("API_BASE_URL=$ApiBaseUrl"))
        $dartDefines = "-Pdart-defines=$defines"
    }
    $variants = if ($Audience -eq 'both') { @('farmer', 'team') } else { @($Audience) }
    $outputDirectory = Join-Path $mobileRoot 'build/apks'
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    foreach ($variant in $variants) {
        $target = if ($variant -eq 'team') { 'lib/main_team.dart' } else { 'lib/main.dart' }
        $task = if ($variant -eq 'team') { 'assembleTeamRelease' } else { 'assembleFarmerRelease' }
        $gradleArguments = @(
            $task, '-Ptarget-platform=android-arm,android-arm64,android-x64',
            "-Ptarget=$target", '-Pdart-obfuscation=false',
            '-Ptrack-widget-creation=false', '-Ptree-shake-icons=true', '--console=plain'
        )
        if ($dartDefines) { $gradleArguments += $dartDefines }
        Push-Location 'android'
        try { Invoke-Checked -Executable '.\gradlew.bat' -Arguments $gradleArguments }
        finally { Pop-Location }
        $apk = Join-Path $mobileRoot "build/app/outputs/flutter-apk/app-$variant-release.apk"
        if (-not (Test-Path -LiteralPath $apk)) { throw "Gradle did not produce the $variant APK." }
        $destination = Join-Path $outputDirectory "krishi-$variant.apk"
        Copy-Item -LiteralPath $apk -Destination $destination -Force
        if ($variant -eq 'farmer') {
            # Keep earlier shared local links pointing to the current farmer APK.
            Copy-Item -LiteralPath $apk -Destination (Join-Path $mobileRoot 'build/app/outputs/flutter-apk/app-release.apk') -Force
        }
        Write-Host "APK ready: $destination"
    }
} finally {
    $env:JAVA_HOME = $previousJava
    $env:PATH = $previousPath
    Pop-Location
}
