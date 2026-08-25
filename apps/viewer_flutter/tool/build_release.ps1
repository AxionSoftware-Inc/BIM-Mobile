param(
    [ValidateSet('apk', 'aab', 'both')]
    [string]$Artifact = 'both',
    [string]$VersionName = '0.2.0',
    [int]$VersionCode = 2
)

$ErrorActionPreference = 'Stop'
$Flutter = 'C:\src\flutter\bin\flutter.bat'
$GitBin = 'C:\Program Files\Git\cmd'
$env:Path = "$GitBin;$env:Path"
$env:REQUIRE_RELEASE_SIGNING = 'true'

if ([string]::IsNullOrWhiteSpace($env:ANDROID_KEYSTORE_PATH) -or
    [string]::IsNullOrWhiteSpace($env:ANDROID_KEYSTORE_PASSWORD) -or
    [string]::IsNullOrWhiteSpace($env:ANDROID_KEY_ALIAS) -or
    [string]::IsNullOrWhiteSpace($env:ANDROID_KEY_PASSWORD)) {
    throw 'Set the four ANDROID_* signing environment variables before a production build.'
}

& $Flutter pub get
$defines = @(
    "--dart-define=APP_RELEASE=viewer_flutter@$VersionName+$VersionCode",
    "--dart-define=APP_ENV=production"
)
if (-not [string]::IsNullOrWhiteSpace($env:SENTRY_DSN)) {
    $defines += "--dart-define=SENTRY_DSN=$($env:SENTRY_DSN)"
}

if ($Artifact -eq 'apk' -or $Artifact -eq 'both') {
    & $Flutter build apk --release --build-name $VersionName --build-number $VersionCode @defines
    if ($LASTEXITCODE -ne 0) { throw "APK release build failed with exit code $LASTEXITCODE." }
}
if ($Artifact -eq 'aab' -or $Artifact -eq 'both') {
    & $Flutter build appbundle --release --build-name $VersionName --build-number $VersionCode @defines
    if ($LASTEXITCODE -ne 0) { throw "AAB release build failed with exit code $LASTEXITCODE." }
}
