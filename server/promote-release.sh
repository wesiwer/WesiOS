#!/usr/bin/env bash
set -euo pipefail

# Atomically promotes one application release or model package.
# Usage:
#   promote-release.sh <product> <channel> <version> <source-dir>
# Example:
#   promote-release.sh wesios app 0.9.0 /tmp/release
#   promote-release.sh wesios forecast-model 2026.08.05 /tmp/model

PRODUCT="${1:?product required}"
CHANNEL="${2:?channel required}"
VERSION="${3:?version required}"
SOURCE_DIR="${4:?source directory required}"
ROOT="${ARTIFACT_ROOT:-/srv/wesi-artifacts}"
KEEP_RELEASES="${KEEP_RELEASES:-1}"

safe='^[a-zA-Z0-9._-]+$'
[[ "$PRODUCT" =~ $safe && "$CHANNEL" =~ $safe && "$VERSION" =~ $safe ]] || {
  echo "Invalid product/channel/version" >&2; exit 2;
}
[[ -d "$SOURCE_DIR" ]] || { echo "Source directory not found" >&2; exit 2; }

BASE="$ROOT/$PRODUCT/$CHANNEL"
RELEASES="$BASE/releases"
TARGET="$RELEASES/$VERSION"
STAGING="$RELEASES/.staging-$VERSION-$$"
LOCK="$BASE/.promote.lock"

mkdir -p "$RELEASES"
exec 9>"$LOCK"
flock -x 9

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -a "$SOURCE_DIR"/. "$STAGING"/

# Every published file gets a checksum. Existing manifest is preserved.
(
  cd "$STAGING"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
  sha256sum -c SHA256SUMS >/dev/null
)

rm -rf "$TARGET"
mv "$STAGING" "$TARGET"
ln -sfn "releases/$VERSION" "$BASE/latest.new"
mv -Tf "$BASE/latest.new" "$BASE/latest"

# Keep only the configured number of complete releases. `latest` is a symlink.
mapfile -t old < <(find "$RELEASES" -mindepth 1 -maxdepth 1 -type d ! -name '.staging-*' -printf '%T@ %p\n' | sort -nr | awk '{print $2}')
for ((i=KEEP_RELEASES; i<${#old[@]}; i++)); do
  rm -rf -- "${old[$i]}"
done

# Remove abandoned staging directories older than one day.
find "$RELEASES" -mindepth 1 -maxdepth 1 -type d -name '.staging-*' -mtime +1 -exec rm -rf {} +

echo "Promoted $PRODUCT/$CHANNEL/$VERSION"
readlink -f "$BASE/latest"
