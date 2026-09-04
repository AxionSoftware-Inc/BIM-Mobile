# Tablet BIM production release

The app version is controlled by `apps/viewer_flutter/pubspec.yaml`. The current
release line is `0.2.10+12` (`versionName` `0.2.10`, Android `versionCode` `12`).

## Required release inputs

Create a private Android upload/release keystore and set these environment
variables in the release machine or CI secret store:

```powershell
$env:ANDROID_KEYSTORE_PATH = 'C:\secure\tablet-bim-upload.jks'
$env:ANDROID_KEYSTORE_PASSWORD = '...'
$env:ANDROID_KEY_ALIAS = 'tablet-bim'
$env:ANDROID_KEY_PASSWORD = '...'
$env:SENTRY_DSN = 'https://public-key@o0.ingest.sentry.io/project-id'
```

`SENTRY_DSN` is optional for local verification but required for production
crash reporting and analytics events. The build never stores the DSN or signing
secrets in the repository.

Run from `apps/viewer_flutter`:

```powershell
.\tool\build_release.ps1 -Artifact both -VersionName 0.2.10 -VersionCode 12
```

The script refuses to build a production artifact without release signing
credentials. The generated APK/AAB are ready for Play Console upload; Android
native symbols and Sentry debug symbols should be uploaded as part of the CI
release job before rollout.
