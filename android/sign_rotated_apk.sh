#!/usr/bin/env bash
# Re-signs a release APK with the original key plus the rotated key (APK Signature Scheme v3 key rotation).
#
# v1/v2 signatures stay on the original key, so Android 5-8 keep accepting updates. On Android 9+ the v3 block is
# signed with the new key and carries the lineage (old key -> new key), so installs move to the new key and then
# refuse updates signed only with the old one.
#
# Usage: sign_rotated_apk.sh <app-release.apk>
# Env:   OLD_KEYSTORE_PATH OLD_KEYSTORE_PASSWORD OLD_KEY_ALIAS [OLD_KEY_PASSWORD]
#        NEW_KEYSTORE_PATH NEW_KEYSTORE_PASSWORD NEW_KEY_ALIAS [NEW_KEY_PASSWORD]
#        LINEAGE_PATH      (from `apksigner rotate`)
#        ANDROID_HOME or ANDROID_SDK_ROOT (build-tools 33+)
set -euo pipefail

APK="${1:?usage: sign_rotated_apk.sh <apk>}"
: "${OLD_KEYSTORE_PATH:?}" "${OLD_KEYSTORE_PASSWORD:?}" "${OLD_KEY_ALIAS:?}"
: "${NEW_KEYSTORE_PATH:?}" "${NEW_KEYSTORE_PASSWORD:?}" "${NEW_KEY_ALIAS:?}"
: "${LINEAGE_PATH:?}"
OLD_KEY_PASSWORD="${OLD_KEY_PASSWORD:-$OLD_KEYSTORE_PASSWORD}"
NEW_KEY_PASSWORD="${NEW_KEY_PASSWORD:-$NEW_KEYSTORE_PASSWORD}"
# Passwords reach apksigner through env:, never on the command line.
export OLD_KEYSTORE_PASSWORD OLD_KEY_PASSWORD NEW_KEYSTORE_PASSWORD NEW_KEY_PASSWORD

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$SDK" ] || { echo "ANDROID_HOME / ANDROID_SDK_ROOT is not set" >&2; exit 1; }
BT_VERSION=$(ls "$SDK/build-tools" | sort -V | tail -n 1)
if [ "${BT_VERSION%%.*}" -lt 33 ]; then
  echo "build-tools $BT_VERSION is too old for --rotation-min-sdk-version; need 33+" >&2
  exit 1
fi
APKSIGNER="$SDK/build-tools/$BT_VERSION/apksigner"
[ -f "$APKSIGNER" ] || APKSIGNER="$APKSIGNER.bat"

SIGNED="$APK.rotated.apk"
# --rotation-min-sdk-version 28: rotate on every v3-capable device, not just Android 13+ (apksigner's default).
"$APKSIGNER" sign \
  --lineage "$LINEAGE_PATH" \
  --rotation-min-sdk-version 28 \
  --ks "$OLD_KEYSTORE_PATH" --ks-key-alias "$OLD_KEY_ALIAS" \
  --ks-pass env:OLD_KEYSTORE_PASSWORD --key-pass env:OLD_KEY_PASSWORD \
  --next-signer \
  --ks "$NEW_KEYSTORE_PATH" --ks-key-alias "$NEW_KEY_ALIAS" \
  --ks-pass env:NEW_KEYSTORE_PASSWORD --key-pass env:NEW_KEY_PASSWORD \
  --out "$SIGNED" "$APK"

# Refuse to publish unless the APK verifies and carries exactly the lineage we meant to apply.
VERIFY=$("$APKSIGNER" verify -v --print-certs "$SIGNED")
echo "$VERIFY" | grep -q "Verified using v2 scheme (APK Signature Scheme v2): true" \
  || { echo "$VERIFY" >&2; echo "v2 signature (original key) missing" >&2; exit 1; }
echo "$VERIFY" | grep -q "Verified using v3 scheme (APK Signature Scheme v3): true" \
  || { echo "$VERIFY" >&2; echo "v3 signature (rotated key) missing" >&2; exit 1; }

EXPECTED_LINEAGE=$("$APKSIGNER" lineage --in "$LINEAGE_PATH" --print-certs | grep -i "SHA-256")
APK_LINEAGE=$("$APKSIGNER" lineage --in "$SIGNED" --print-certs | grep -i "SHA-256")
if [ "$EXPECTED_LINEAGE" != "$APK_LINEAGE" ] || [ "$(echo "$APK_LINEAGE" | wc -l)" -lt 2 ]; then
  echo "APK lineage does not match $LINEAGE_PATH" >&2
  echo "expected:"; echo "$EXPECTED_LINEAGE"; echo "apk:"; echo "$APK_LINEAGE"
  exit 1
fi

mv -f "$SIGNED" "$APK"
rm -f "$SIGNED.idsig" "$APK.idsig"
echo "Signed $APK with key rotation:"
echo "$APK_LINEAGE"
