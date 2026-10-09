#!/bin/sh
set -eu
: "${Q_INTERIOR_ANDROID_KEYSTORE:?GitOps File variable is required}"
: "${Q_INTERIOR_ANDROID_STORE_PASSWORD:?}"
: "${Q_INTERIOR_ANDROID_KEY_ALIAS:?}"
: "${Q_INTERIOR_ANDROID_KEY_PASSWORD:?}"
: "${Q_INTERIOR_API_URL:?Public API URL must be configured in GitOps}"
: "${Q_INTERIOR_FIREBASE_CREDENTIALS:?GitOps File variable is required}"
: "${Q_INTERIOR_FIREBASE_ANDROID_APP_ID:?}"
: "${Q_INTERIOR_FIREBASE_GROUPS:?}"
test -f "$Q_INTERIOR_ANDROID_KEYSTORE"
test -f "$Q_INTERIOR_FIREBASE_CREDENTIALS"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export GOOGLE_APPLICATION_CREDENTIALS="$Q_INTERIOR_FIREBASE_CREDENTIALS"
cd q-source
sh gradlew :androidApp:assembleRelease --no-daemon
apk=androidApp/build/outputs/apk/release/androidApp-release.apk
test -f "$apk"
npm install --prefix ../firebase-cli firebase-tools@14.20.0
../firebase-cli/node_modules/.bin/firebase appdistribution:distribute "$apk" \
  --app "$Q_INTERIOR_FIREBASE_ANDROID_APP_ID" --groups "$Q_INTERIOR_FIREBASE_GROUPS" \
  --release-notes "Q Interior $Q_SOURCE_SHA (pipeline $CI_PIPELINE_ID)"
