#!/usr/bin/env python3
"""Connect the generated Flutter Android project to a CI release keystore."""

from pathlib import Path


gradle_path = Path("android/app/build.gradle.kts")
if not gradle_path.is_file():
    raise SystemExit(f"Generated Gradle file is missing: {gradle_path}")

source = gradle_path.read_text(encoding="utf-8")
if "wesiAeroReleaseProperties" in source:
    raise SystemExit("Android release signing is already configured")

source = "import java.util.Properties\n\n" + source

properties_block = """
val wesiAeroReleaseProperties = Properties()
val wesiAeroReleasePropertiesFile = rootProject.file("key.properties")
check(wesiAeroReleasePropertiesFile.exists()) {
    "key.properties is required for a Wesi Aero release build"
}
wesiAeroReleasePropertiesFile.inputStream().use {
    wesiAeroReleaseProperties.load(it)
}
"""

android_marker = "\nandroid {\n"
if android_marker not in source:
    raise SystemExit("Could not find the Android block in build.gradle.kts")
source = source.replace(
    android_marker,
    f"\n{properties_block}\nandroid {{\n"
    "    signingConfigs {\n"
    "        create(\"release\") {\n"
    "            keyAlias = wesiAeroReleaseProperties[\"keyAlias\"] as String\n"
    "            keyPassword = wesiAeroReleaseProperties[\"keyPassword\"] as String\n"
    "            storeFile = file(wesiAeroReleaseProperties[\"storeFile\"] as String)\n"
    "            storePassword = wesiAeroReleaseProperties[\"storePassword\"] as String\n"
    "        }\n"
    "    }\n",
    1,
)

debug_signing = 'signingConfig = signingConfigs.getByName("debug")'
if debug_signing not in source:
    raise SystemExit("Could not find Flutter's default release signing line")
source = source.replace(
    debug_signing,
    'signingConfig = signingConfigs.getByName("release")',
    1,
)

gradle_path.write_text(source, encoding="utf-8")
print(f"Configured release signing in {gradle_path}")
