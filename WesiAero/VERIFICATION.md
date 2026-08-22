# Wesi Aero Verification

The goal is to let a reviewer verify important security claims without trusting the Wesi Aero UI or a prebuilt APK. This is **verification evidence**, not a substitute for an external audit.

## 1. Verify source pins

From the repository root:

```bash
python3 WesiAero/scripts/verify_security_invariants.py
```

This checks the security-critical dependency lock against build scripts, verifies that Android release workflows use approved immutable action SHAs, checks fail-closed server configuration markers, checks exact WireGuard/AmneziaWG profile separation, and checks the Rust supervisor/toolchain pins.

## 2. Verify the Rust lifecycle core

```bash
cd WesiAero/core/wesi-tunnel-core
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
```

The tests cover mandatory health verification before `Connected`, stale callback rejection, serialized fallback through `StopAll`, fail-closed behavior after exhausted fallbacks, and explicit disconnect behavior.

## 3. Verify Xray binary input

The approved AndroidLibXrayLite input is recorded in `DEPENDENCIES.lock.json`. The downloader validates SHA-256 before moving the file into the Android build:

```bash
python3 WesiAero/scripts/download_xray_aar.py
sha256sum WesiAero/android/app/libs/libv2ray.aar
```

The expected SHA-256 is:

`3d43b9344723e9c0625527de4f2bea0ee02c21180224e5ecab3384af143ca6d0`

Its source release is AndroidLibXrayLite `v26.5.19`, source commit `4c3a3cd051ac6a10d27ba1347a05fff2697ea272`.

## 4. Verify sing-box source identity

The Android build clones sing-box `v1.13.18` but does not trust the mutable tag name alone. It resolves `HEAD` and fails unless it equals:

`45ca32dcb966f07f97fc888fe8586e359dbe8405`

The upstream commit is signed/verified by GitHub at the time this lock was created. Reviewers should independently verify the upstream signature and repository history.

## 5. Verify HEV and AmneziaWG inputs

- HEV socks5 tunnel commit: `64cc609f945253b0e9ebc56317d544268f3c68c1`
- AmneziaWG Android Maven version: `2.3.7`
- Android NDK: `28.0.13004108`
- Go: `1.24.13`
- Flutter: `3.47.1`
- Rust: `1.88.0`

These values are centralized in `DEPENDENCIES.lock.json` and enforced by the security verification workflow.

## 6. Verify release evidence

Every signed APK build writes a `.sha256` file. The security verification workflow additionally emits `wesi-aero-source-manifest.sha256`, a hash manifest of security-relevant source/configuration files for the exact Git commit.

A stronger production release process should run at least two independent builders and compare resulting normalized APK contents. Full byte-for-byte APK reproducibility is a separate milestone because Android/Gradle packaging can contain environment-dependent metadata.

## 7. What is not independently verified yet

- there is no third-party penetration/security audit;
- the relay OS image is not yet an independently reproducible diskless image;
- default prototype tunnel credentials are not yet per-device;
- the Rust supervisor is not yet the Android runtime authority until its JNI/Kotlin adapter replaces the current Kotlin lifecycle decisions;
- provider-side UDP/51821 remains an external prerequisite for a full AmneziaWG handshake test.

These limitations should stay visible until their corresponding production gates are actually satisfied.
