#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
cd "$repo_root"

swift build -c release

binary_path="$(swift build -c release --show-bin-path)/MarkReview"
staging_dir=$(mktemp -d -t MarkReviewRelease)
trap 'rm -rf "$staging_dir"' EXIT
app_path="$staging_dir/MarkReview.app"
install_path="/Applications/MarkReview.app"
backup_path="$staging_dir/previous-MarkReview.app"
icon_info_path="$staging_dir/Info.plist.partial"

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

codesign --force --deep --sign - --timestamp=none "$app_path"
codesign --verify --deep --strict "$app_path"

if [[ -e "$install_path" ]]; then
  mv "$install_path" "$backup_path"
fi

if ! ditto "$app_path" "$install_path"; then
  if [[ -e "$backup_path" ]]; then
    mv "$backup_path" "$install_path"
  fi
  exit 1
fi

if ! codesign --verify --deep --strict "$install_path"; then
  mv "$install_path" "$staging_dir/failed-MarkReview.app"
  if [[ -e "$backup_path" ]]; then
    mv "$backup_path" "$install_path"
  fi
  exit 1
fi

print -r -- "Installed ad-hoc signed release at $install_path"
codesign -dv --verbose=2 "$install_path" 2>&1 | rg 'Identifier=|Signature=|TeamIdentifier='
