#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
cd "$repo_root"

swift build -c release

binary_path=$(swift build -c release --show-bin-path)/MarkReview
app_path="$repo_root/MarkReview.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/MarkReview"
cp "$repo_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
icon_info_path=$(mktemp -t MarkReviewIconInfo)
trap 'rm -f "$icon_info_path"' EXIT
xcrun actool \
  --compile "$app_path/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$icon_info_path" \
  "$repo_root/Resources/Assets.xcassets" >/dev/null

echo "Built $app_path"
