#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ! -f "$project_root/pubspec.yaml" ]] || \
   ! grep -q '^name: wesi_aero$' "$project_root/pubspec.yaml"; then
  echo "Run this script from the Wesi Aero project." >&2
  exit 2
fi
if [[ -d "$project_root/android" || -d "$project_root/windows" ]]; then
  echo "android/ or windows/ already exists; refusing to overwrite." >&2
  exit 3
fi

bootstrap_dir="$(mktemp -d)"
trap 'rm -rf "$bootstrap_dir"' EXIT

flutter create \
  --platforms=android,windows \
  --org com.wesi \
  --project-name wesi_aero \
  "$bootstrap_dir/wesi_aero"

cp -R "$bootstrap_dir/wesi_aero/android" "$project_root/android"
cp -R "$bootstrap_dir/wesi_aero/windows" "$project_root/windows"

android_gradle="$project_root/android/app/build.gradle.kts"
if [[ -f "$android_gradle" ]]; then
  sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 23/' "$android_gradle"
fi

android_manifest="$project_root/android/app/src/main/AndroidManifest.xml"
if [[ -f "$android_manifest" ]] && ! grep -q 'android:scheme="wesi-aero"' "$android_manifest"; then
  awk '
    /        <\/activity>/ && !done {
      print "            <meta-data"
      print "                android:name=\"flutter_deeplinking_enabled\""
      print "                android:value=\"false\" />"
      print "            <intent-filter>"
      print "                <action android:name=\"android.intent.action.VIEW\" />"
      print "                <category android:name=\"android.intent.category.DEFAULT\" />"
      print "                <category android:name=\"android.intent.category.BROWSABLE\" />"
      print "                <data"
      print "                    android:scheme=\"wesi-aero\""
      print "                    android:host=\"payment-return\" />"
      print "            </intent-filter>"
      done=1
    }
    { print }
  ' "$android_manifest" > "$android_manifest.tmp"
  mv "$android_manifest.tmp" "$android_manifest"
fi

cd "$project_root"
flutter pub get
echo "Android and Windows platform scaffolds are ready."
