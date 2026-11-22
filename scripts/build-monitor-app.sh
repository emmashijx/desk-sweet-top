#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
output_app="$project_dir/output/local-test/HomeSweetHome.app"
resource_dir="$output_app/Contents/Resources"
mkdir -p "$output_app/Contents/MacOS" "$resource_dir/layers"
cp "$project_dir/app/Info.plist" "$output_app/Contents/Info.plist"
cp "$project_dir/app/layout.json" "$resource_dir/layout.json"
for locale in "$project_dir"/app/Localizations/*.lproj; do
  mkdir -p "$resource_dir/${locale:t}"
  cp "$locale"/*.strings "$resource_dir/${locale:t}/"
done
cp "$project_dir"/assets/design/v3/layers-v3-22-refined/png-layers/*.png "$resource_dir/layers/"
xcrun swiftc -swift-version 5 -O -framework AppKit -framework ApplicationServices -framework ImageIO \
  "$project_dir"/app/*.swift -o "$output_app/Contents/MacOS/HomeSweetHome"
codesign --force --sign - "$output_app"
print "$output_app"
