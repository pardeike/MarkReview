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

echo "Built $app_path"
