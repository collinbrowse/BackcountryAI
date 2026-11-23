#!/usr/bin/env bash
# Lists the privacy manifests in an archived app and the required-reason APIs its binaries reference, so
# Sources/PrivacyInfo.xcprivacy can be checked against them. Xcode's Organizer can make a Privacy Report, but only
# from the window; this is the command-line version of the part that matters (Apple's list:
# https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
#
#   xcodebuild archive -project BackcountryAI.xcodeproj -scheme BackcountryAI -configuration Release \
#     -destination 'generic/platform=iOS' -archivePath build/BackcountryAI.xcarchive -allowProvisioningUpdates
#   scripts/privacy-scan.sh build/BackcountryAI.xcarchive
set -euo pipefail

archive="${1:?usage: scripts/privacy-scan.sh path/to/BackcountryAI.xcarchive}"
app="$archive/Products/Applications/BackcountryAI.app"
[ -d "$app" ] || { echo "No BackcountryAI.app in $archive" >&2; exit 1; }

echo "Privacy manifests"
find "$app" -name PrivacyInfo.xcprivacy | while read -r m; do
  echo "  ${m#"$app"/}"
  plutil -extract NSPrivacyAccessedAPITypes json -o - "$m" 2>/dev/null \
    | python3 -c 'import json,sys; [print("    ", t["NSPrivacyAccessedAPIType"].removeprefix("NSPrivacyAccessedAPICategory"), ", ".join(t["NSPrivacyAccessedAPITypeReasons"])) for t in json.load(sys.stdin)]'
done

echo
echo "Required-reason APIs referenced (category: symbols)"
find "$app" -type f -perm +111 | while read -r bin; do
  file "$bin" | grep -q Mach-O || continue
  syms="$(nm -u "$bin" 2>/dev/null || true)"
  strs="$(strings -a "$bin" 2>/dev/null || true)"
  hits=()
  grep -qE '^_(stat|fstat|lstat|fstatat|getattrlist|fgetattrlist|getattrlistbulk|getattrlistat)$|NSFileCreationDate|NSFileModificationDate|NSURLCreationDateKey|NSURLContentModificationDateKey|NSURLAttributeModificationDateKey|contentModificationDate|creationDate' <<<"$syms" \
    && hits+=("FileTimestamp")
  grep -qE '^_(mach_absolute_time)$' <<<"$syms" || grep -q 'systemUptime' <<<"$strs" && hits+=("SystemBootTime")
  grep -qE '^_(statfs|fstatfs|statvfs|fstatvfs)$|NSFileSystemFreeSize|NSFileSystemSize|NSURLVolume(Available|Total)Capacity|volumeAvailableCapacity|volumeTotalCapacity' <<<"$syms" \
    && hits+=("DiskSpace")
  grep -q 'activeInputModes' <<<"$strs" && hits+=("ActiveKeyboards")
  grep -qE 'NSUserDefaults|UserDefaults' <<<"$syms$strs" && hits+=("UserDefaults")
  echo "  ${bin#"$app"/}: ${hits[*]:-none}"
done
