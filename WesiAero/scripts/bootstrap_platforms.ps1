$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Pubspec = Join-Path $ProjectRoot "pubspec.yaml"
if (-not (Test-Path $Pubspec) -or
    -not (Select-String -Path $Pubspec -Pattern '^name: wesi_aero$' -Quiet)) {
  throw "Run this script from the Wesi Aero project."
}
if ((Test-Path (Join-Path $ProjectRoot "android")) -or
    (Test-Path (Join-Path $ProjectRoot "windows"))) {
  throw "android/ or windows/ already exists; refusing to overwrite."
}

$BootstrapRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wesi-aero-" + [guid]::NewGuid())
try {
  flutter create `
    --platforms=android,windows `
    --org com.wesi `
    --project-name wesi_aero `
    (Join-Path $BootstrapRoot "wesi_aero")

  Copy-Item -Recurse (Join-Path $BootstrapRoot "wesi_aero/android") (Join-Path $ProjectRoot "android")
  Copy-Item -Recurse (Join-Path $BootstrapRoot "wesi_aero/windows") (Join-Path $ProjectRoot "windows")

  $AndroidGradle = Join-Path $ProjectRoot "android/app/build.gradle.kts"
  if (Test-Path $AndroidGradle) {
    (Get-Content $AndroidGradle -Raw).Replace(
      "minSdk = flutter.minSdkVersion",
      "minSdk = 23"
    ) | Set-Content $AndroidGradle
  }

  Push-Location $ProjectRoot
  try {
    flutter pub get
  } finally {
    Pop-Location
  }
  Write-Host "Android and Windows platform scaffolds are ready."
} finally {
  if (Test-Path $BootstrapRoot) {
    Remove-Item -Recurse -Force $BootstrapRoot
  }
}
