#!/bin/bash
set -eu
: "${Q_INTERIOR_IOS_P12:?GitOps File variable is required}"
: "${Q_INTERIOR_IOS_P12_PASSWORD:?}"
: "${Q_INTERIOR_IOS_PROFILE:?GitOps File variable is required}"
: "${Q_INTERIOR_IOS_TEAM_ID:?}"
: "${Q_INTERIOR_IOS_EXPORT_OPTIONS:?GitOps File variable is required}"
: "${Q_INTERIOR_API_URL:?}"
: "${Q_INTERIOR_FIREBASE_CREDENTIALS:?GitOps File variable is required}"
: "${Q_INTERIOR_FIREBASE_IOS_APP_ID:?}"
: "${Q_INTERIOR_FIREBASE_GROUPS:?}"
command -v xcodegen >/dev/null
command -v xcodebuild >/dev/null
command -v firebase >/dev/null
export GOOGLE_APPLICATION_CREDENTIALS="$Q_INTERIOR_FIREBASE_CREDENTIALS"
umask 077
temp_dir=$(mktemp -d)
keychain="$temp_dir/build.keychain-db"
keychain_password=$(openssl rand -hex 24)
profile_installed=''
original_keychains=()
while IFS= read -r line; do
  path="${line#*\"}"
  path="${path%\"*}"
  original_keychains+=("$path")
done < <(security list-keychains -d user)
cleanup() {
  security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1 || true
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  if [ -n "$profile_installed" ]; then rm -f "$profile_installed"; fi
  rm -rf "$temp_dir"
}
trap cleanup EXIT INT TERM
security create-keychain -p "$keychain_password" "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security list-keychains -d user -s "$keychain" "${original_keychains[@]}"
security set-keychain-settings -lut 21600 "$keychain"
security import "$Q_INTERIOR_IOS_P12" -k "$keychain" -P "$Q_INTERIOR_IOS_P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security cms -D -i "$Q_INTERIOR_IOS_PROFILE" > "$temp_dir/profile.plist"
profile_uuid=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$temp_dir/profile.plist")
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
profile_installed="$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
test ! -e "$profile_installed" || { profile_installed=''; echo 'Use an isolated signing runner' >&2; exit 1; }
cp "$Q_INTERIOR_IOS_PROFILE" "$profile_installed"
cd q-source
sh gradlew :composeApp:assembleQInteriorSharedReleaseXCFramework --no-daemon
cd iosApp
xcodegen generate
xcodebuild -project QInterior.xcodeproj -scheme QInterior -configuration Release \
  -destination 'generic/platform=iOS' -archivePath ../build/QInterior.xcarchive archive \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$Q_INTERIOR_IOS_TEAM_ID" \
  PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" OTHER_CODE_SIGN_FLAGS="--keychain $keychain" \
  Q_INTERIOR_API_URL="$Q_INTERIOR_API_URL" CI_PIPELINE_IID="$CI_PIPELINE_IID"
xcodebuild -exportArchive -archivePath ../build/QInterior.xcarchive \
  -exportOptionsPlist "$Q_INTERIOR_IOS_EXPORT_OPTIONS" -exportPath ../build/ipa
ipa=../build/ipa/QInterior.ipa
test -f "$ipa"
firebase appdistribution:distribute "$ipa" --app "$Q_INTERIOR_FIREBASE_IOS_APP_ID" \
  --groups "$Q_INTERIOR_FIREBASE_GROUPS" --release-notes "Q Interior $Q_SOURCE_SHA (pipeline $CI_PIPELINE_ID)"
