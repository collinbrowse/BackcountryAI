# Shared App Store Connect setup for scripts that upload asset packs. Source it, then call asc_init.
#
# Needs an App Store Connect API key (Users and Access › Integrations › App Store Connect API, role App Manager or
# higher). Put its .p8 file in ~/private_keys/AuthKey_<KEY_ID>.p8 and the IDs in .asc.env at the repository root
# (see .asc.env.example). .asc.env is git-ignored.

# Checks the credentials and sets ASC_APP_ID and AUTH (the altool flags). Exits with a message if anything is missing.
asc_init() {
  local root="$1"
  [ -f "$root/.asc.env" ] || { echo "STOPPED: no .asc.env. Copy .asc.env.example to .asc.env and fill it in, or pass --no-upload." >&2; exit 1; }
  # shellcheck disable=SC1091
  source "$root/.asc.env"
  : "${ASC_KEY_ID:?set ASC_KEY_ID in .asc.env}" "${ASC_ISSUER_ID:?set ASC_ISSUER_ID in .asc.env}"
  : "${ASC_APP_ID:?set ASC_APP_ID (the app Apple ID, a number) in .asc.env}"
  local keyfile="" d
  for d in "$root/private_keys" ~/private_keys ~/.private_keys ~/.appstoreconnect/private_keys "${API_PRIVATE_KEYS_DIR:-}"; do
    [ -n "$d" ] && [ -f "$d/AuthKey_$ASC_KEY_ID.p8" ] && keyfile="$d/AuthKey_$ASC_KEY_ID.p8" && break
  done
  [ -n "$keyfile" ] || { echo "STOPPED: AuthKey_$ASC_KEY_ID.p8 not found in ~/private_keys or ~/.appstoreconnect/private_keys." >&2; exit 1; }
  AUTH=(--api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID")
  printf '\n== Checking App Store Connect access\n'
  xcrun altool --list-asset-packs --apple-id "$ASC_APP_ID" "${AUTH[@]}" \
    || { echo "STOPPED: App Store Connect refused the key or app ID. Check .asc.env." >&2; exit 1; }
}

# Uploads an .aar, waits for Apple to process it, and lists the pack's versions. Logs to $3.
asc_upload() {
  local aar="$1" id="$2" log="$3"
  xcrun altool --upload-asset-pack "$aar" --apple-id "$ASC_APP_ID" "${AUTH[@]}" --wait 2>&1 | tee "$log" \
    || { echo "STOPPED: upload failed; see $log" >&2; exit 1; }
  printf '\n== Versions of %s on App Store Connect\n' "$id"
  xcrun altool --list-asset-pack-versions --apple-id "$ASC_APP_ID" --asset-pack-identifier "$id" "${AUTH[@]}" \
    | tee -a "$log" || true
}
