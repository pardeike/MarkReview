#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
expected_team_id="${MARKREVIEW_TEAM_ID:-W65292CD8T}"
signing_identity="${MARKREVIEW_CODESIGN_IDENTITY:-Developer ID Application: Andreas Pardeike ($expected_team_id)}"
signing_keychain="${MARKREVIEW_CODESIGN_KEYCHAIN:-}"
notary_profile="${MARKREVIEW_NOTARY_PROFILE:-brrainz-notary}"
notary_keychain="${MARKREVIEW_NOTARY_KEYCHAIN:-}"
staging_dir=""
notary_dir=""
install_staging_dir=""
staged_app_path=""
backup_app_path=""
install_path="/Applications/MarkReview.app"
install_verified=false

verify_release_signature() {
  local app_path="$1"
  local signature_details
  local entitlements_path
  local get_task_allow

  signature_details="$(codesign --display --verbose=4 "$app_path" 2>&1)"
  if [[ "$signature_details" != *"Authority=Developer ID Application:"* ]]; then
    print -u2 -- "$app_path is not signed by a Developer ID Application authority."
    return 1
  fi
  if [[ "$signature_details" != *"Identifier=com.markreview.app"* ]]; then
    print -u2 -- "$app_path has an unexpected code-signing identifier."
    return 1
  fi
  if [[ "$signature_details" != *"TeamIdentifier=$expected_team_id"* ]]; then
    print -u2 -- "$app_path has an unexpected code-signing Team ID."
    return 1
  fi
  if [[ "$signature_details" != *"flags=0x10000(runtime)"* ]]; then
    print -u2 -- "$app_path is not signed with the hardened runtime."
    return 1
  fi
  if [[ "$signature_details" != *"Timestamp="* || "$signature_details" == *"Timestamp=none"* ]]; then
    print -u2 -- "$app_path is missing a trusted signing timestamp."
    return 1
  fi

  entitlements_path="$(mktemp "${TMPDIR:-/tmp}/markreview-entitlements.XXXXXX")"
  if ! codesign --display --entitlements :- "$app_path" >"$entitlements_path" 2>/dev/null; then
    rm -f "$entitlements_path"
    print -u2 -- "Could not inspect entitlements for $app_path."
    return 1
  fi
  get_task_allow="$(
    /usr/libexec/PlistBuddy \
      -c 'Print :com.apple.security.get-task-allow' \
      "$entitlements_path" 2>/dev/null || true
  )"
  rm -f "$entitlements_path"
  if [[ "$get_task_allow" == "true" ]]; then
    print -u2 -- "$app_path unexpectedly allows debugger attachment in Release."
    return 1
  fi
}

verify_notarization() {
  local app_path="$1"
  local gatekeeper_details

  if ! xcrun stapler validate "$app_path" >/dev/null; then
    print -u2 -- "$app_path does not contain a valid stapled notarization ticket."
    return 1
  fi
  if ! gatekeeper_details="$(spctl --assess --type execute --verbose=2 "$app_path" 2>&1)"; then
    print -u2 -- "$gatekeeper_details"
    return 1
  fi
  if [[ "$gatekeeper_details" != *"source=Notarized Developer ID"* ]]; then
    print -u2 -- "$app_path did not pass Gatekeeper as a notarized Developer ID app:"
    print -u2 -- "$gatekeeper_details"
    return 1
  fi
}

cleanup() {
  if [[ "$install_verified" != true && -n "$install_staging_dir" && -d "$install_staging_dir" ]]; then
    if [[ -n "$backup_app_path" && -e "$backup_app_path" ]]; then
      if [[ -e "$install_path" ]]; then
        rm -rf "$install_path"
      fi
      mv "$backup_app_path" "$install_path"
    elif [[ -n "$staged_app_path" && ! -e "$staged_app_path" && -e "$install_path" ]]; then
      rm -rf "$install_path"
    fi
  fi
  if [[ -n "$install_staging_dir" && -d "$install_staging_dir" ]]; then
    rm -rf "$install_staging_dir"
  fi
  if [[ -n "$staging_dir" && -d "$staging_dir" ]]; then
    rm -rf "$staging_dir"
  fi
  if [[ -n "$notary_dir" && -d "$notary_dir" ]]; then
    rm -rf "$notary_dir"
  fi
}
trap cleanup EXIT

cd "$repo_root"

identity_lookup_args=(-v -p codesigning)
if [[ -n "$signing_keychain" ]]; then
  identity_lookup_args+=("$signing_keychain")
fi
available_identities="$(security find-identity "${identity_lookup_args[@]}")"
if [[ "$available_identities" != *"$signing_identity"* ]]; then
  print -u2 -- "Code-signing identity not found: $signing_identity"
  exit 1
fi

plutil -lint "$repo_root/Resources/Info.plist" >/dev/null
swift test
swift build -c release --product MarkReview

binary_directory="$(swift build -c release --show-bin-path)"
binary_path="$binary_directory/MarkReview"
staging_dir="$(mktemp -d -t MarkReviewRelease)"
app_path="$staging_dir/MarkReview.app"
icon_info_path="$staging_dir/Info.plist.partial"
launch_services_register="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

make_document_icon() {
  local source_path="$1"
  local icon_name="$2"
  local iconset_path="$staging_dir/${icon_name}.iconset"
  local target_path="$app_path/Contents/Resources/${icon_name}.icns"

  if [[ ! -f "$source_path" ]]; then
    print -u2 -- "Missing document icon source: $source_path"
    exit 1
  fi

  mkdir -p "$iconset_path"
  local icon_spec size filename
  for icon_spec in \
    "16:icon_16x16.png" \
    "32:icon_16x16@2x.png" \
    "32:icon_32x32.png" \
    "64:icon_32x32@2x.png" \
    "128:icon_128x128.png" \
    "256:icon_128x128@2x.png" \
    "256:icon_256x256.png" \
    "512:icon_256x256@2x.png" \
    "512:icon_512x512.png" \
    "1024:icon_512x512@2x.png"; do
    size="${icon_spec%%:*}"
    filename="${icon_spec#*:}"
    sips -z "$size" "$size" "$source_path" --out "$iconset_path/$filename" >/dev/null
  done
  iconutil -c icns "$iconset_path" -o "$target_path"

  if [[ ! -s "$target_path" ]]; then
    print -u2 -- "Failed to create document icon: $target_path"
    exit 1
  fi
}

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/MarkReview"
cp "$repo_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
xcrun actool \
  --compile "$app_path/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$icon_info_path" \
  "$repo_root/Resources/Assets.xcassets" >/dev/null

if [[ ! -f "$app_path/Contents/Resources/AppIcon.icns" ]]; then
  print -u2 -- "Asset catalog did not produce AppIcon.icns; refusing to install an app without an icon."
  exit 1
fi

make_document_icon "$repo_root/Resources/DocumentIcons/MarkdownDocument.png" "MarkdownDocument"
make_document_icon "$repo_root/Resources/DocumentIcons/MarkReviewDocument.png" "MarkReviewDocument"

codesign_args=(
  --force
  --timestamp
  --options runtime
  --sign "$signing_identity"
)
if [[ -n "$signing_keychain" ]]; then
  codesign_args+=(--keychain "$signing_keychain")
fi
codesign "${codesign_args[@]}" "$app_path"

codesign --verify --deep --strict "$app_path"
verify_release_signature "$app_path"

bundle_version="$(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist")"
notary_dir="$(mktemp -d "${TMPDIR:-/tmp}/MarkReview-notary.XXXXXX")"
notary_archive="$notary_dir/MarkReview-$bundle_version-notarization.zip"
notary_result="$notary_dir/result.json"
ditto -c -k --keepParent --norsrc "$app_path" "$notary_archive"

notary_args=(--keychain-profile "$notary_profile")
if [[ -n "$notary_keychain" ]]; then
  notary_args+=(--keychain "$notary_keychain")
fi
if xcrun notarytool submit "$notary_archive" \
  "${notary_args[@]}" \
  --wait \
  --output-format json \
  >"$notary_result"; then
  :
else
  submit_exit=$?
  print -u2 -- "Apple notarization submission failed:"
  cat "$notary_result" >&2
  exit "$submit_exit"
fi

notary_status="$(plutil -extract status raw -o - "$notary_result" 2>/dev/null || true)"
notary_id="$(plutil -extract id raw -o - "$notary_result" 2>/dev/null || true)"
if [[ "$notary_status" != "Accepted" ]]; then
  print -u2 -- "Apple notarization was not accepted:"
  cat "$notary_result" >&2
  exit 1
fi
print -r -- "Apple notarization accepted: $notary_id"

xcrun stapler staple "$app_path" >/dev/null
verify_notarization "$app_path"

install_staging_dir="$(mktemp -d /Applications/.MarkReview-install.XXXXXX)"
staged_app_path="$install_staging_dir/MarkReview.app"
backup_app_path="$install_staging_dir/Previous.app"
ditto "$app_path" "$staged_app_path"
codesign --verify --deep --strict "$staged_app_path"
verify_release_signature "$staged_app_path"
verify_notarization "$staged_app_path"

if [[ -e "$install_path" ]]; then
  mv "$install_path" "$backup_app_path"
fi

if ! mv "$staged_app_path" "$install_path"; then
  print -u2 -- "Could not install MarkReview at $install_path"
  exit 1
fi

codesign --verify --deep --strict "$install_path"
verify_release_signature "$install_path"
verify_notarization "$install_path"

bundle_identifier="$(plutil -extract CFBundleIdentifier raw "$install_path/Contents/Info.plist")"
if [[ "$bundle_identifier" != "com.markreview.app" ]]; then
  print -u2 -- "Installed MarkReview has unexpected bundle identifier: $bundle_identifier"
  exit 1
fi

"$launch_services_register" -f "$install_path"

install_verified=true
print -r -- "Installed Developer ID signed and notarized Release at $install_path"
codesign -dv --verbose=2 "$install_path" 2>&1 | rg 'Identifier=|Authority=Developer ID Application:|TeamIdentifier=|Timestamp='
