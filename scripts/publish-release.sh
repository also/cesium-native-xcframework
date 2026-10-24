#!/usr/bin/env bash
# Publish the xcframework built by build-xcframework.sh as a GitHub release.
#
#   scripts/publish-release.sh <tag> [--yes] [--prerelease]
#
# Without --yes it only checks everything and prints what it would publish.
# Tag by cesium-native version plus a build revision, e.g. v0.64.0-1, so a
# rebuild doesn't need a new upstream version.
#
# Uploads CesiumNative.xcframework.zip and THIRD_PARTY_LICENSES. The release
# notes carry the SwiftPM checksum (the zip's SHA-256), the cesium-native and
# vcpkg versions, and the per-slice manifest.
#
# Environment: CESIUM_BUILD_ROOT, as for build-xcframework.sh.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

TAG=""; YES=0; PRERELEASE=()
for arg in "$@"; do
  case "$arg" in
    --yes) YES=1 ;;
    --prerelease) PRERELEASE=(--prerelease) ;;
    -*) die "unknown option $arg" ;;
    *) [[ -z "$TAG" ]] || die "one tag only"; TAG="$arg" ;;
  esac
done
[[ -n "$TAG" ]] || die "usage: $0 <tag> [--yes] [--prerelease]"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${CESIUM_BUILD_ROOT:-$HOME/.cache/cesium-native-xcframework}/out"
ZIP="$OUT_DIR/CesiumNative.xcframework.zip"
MANIFEST="$OUT_DIR/CesiumNative.manifest.txt"
FRAMEWORK="$OUT_DIR/CesiumNative.xcframework"

cd "$REPO_DIR"
command -v gh >/dev/null || die "gh is required"
[[ -f "$ZIP" && -f "$MANIFEST" && -d "$FRAMEWORK" ]] || die "no build in $OUT_DIR; run build-xcframework.sh first"

# The tag must point at a commit that's on the remote, and the tree must be
# clean, so the release can be traced to its build scripts.
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "uncommitted changes"
COMMIT="$(git rev-parse HEAD)"
git fetch -q origin
git branch -r --contains "$COMMIT" | grep -q . || die "HEAD ($COMMIT) isn't pushed; push the branch first"
gh release view "$TAG" >/dev/null 2>&1 && die "release $TAG already exists"

# SwiftPM wants the framework at the zip's top level, and the checksum is the
# zip's SHA-256. Also confirm the zip is what's in the build directory, not an
# older build.
[[ "$(unzip -Z1 "$ZIP" | head -1)" == "CesiumNative.xcframework/" ]] || die "zip doesn't have the framework at its top level"
SUM="$(swift package compute-checksum "$ZIP")"
[[ "$SUM" == "$(tr -d '[:space:]' < "$OUT_DIR/CesiumNative.xcframework.sha256")" ]] || die "zip doesn't match CesiumNative.xcframework.sha256"
SLICES="$(/usr/libexec/PlistBuddy -c Print "$FRAMEWORK/Info.plist" | awk '/LibraryIdentifier/ {print $3}' | sort | tr '\n' ' ')"
[[ -n "$SLICES" ]] || die "couldn't read slices from the framework's Info.plist"

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
{
  echo "CesiumNative xcframework: slices $SLICES"
  echo
  echo "SwiftPM checksum (SHA-256 of the zip):"
  echo
  echo '```'
  echo "$SUM"
  echo '```'
  echo
  echo "Built from \`$COMMIT\` of $(git remote get-url origin | sed -E 's#^.*github.com[:/]##; s#\.git$##')."
  echo
  echo '```'
  cat "$MANIFEST"
  echo '```'
  echo
  echo "The archive does not include SQLite; link the system \`libsqlite3\`."
} > "$NOTES"

echo "tag:      $TAG (at $COMMIT)"
echo "slices:   $SLICES"
echo "zip:      $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "checksum: $SUM"
if [[ $YES -ne 1 ]]; then
  echo
  cat "$NOTES"
  echo
  echo "Dry run. Re-run with --yes to publish."
  exit 0
fi

gh release create "$TAG" "$ZIP" "$REPO_DIR/THIRD_PARTY_LICENSES" \
  --target "$COMMIT" --title "$TAG" --notes-file "$NOTES" ${PRERELEASE[@]+"${PRERELEASE[@]}"}
