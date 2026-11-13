#!/bin/sh
# Creates the fixed signing key for test builds and stores it as secrets of the GitHub repository, so that
# every APK built by CI has the same signature and installs over the previous one.
# Run once, by the repository owner, on their own machine. Needs keytool (JDK), openssl and the gh CLI.
# The key and its password stay outside the repository, in ~/.android/. Keep them: without the key, later
# test builds can no longer be installed over earlier ones. Nothing secret is printed.
# This key is for test builds only; a store release needs its own key, kept more carefully.
set -eu
DIR="$HOME/.android"
KEY="$DIR/slice-n-dice-test.keystore"
PASS="$DIR/slice-n-dice-test.pass"
KEYTOOL=${KEYTOOL:-keytool}

cd "$(dirname "$0")/.."
umask 077
mkdir -p "$DIR"
if [ -e "$KEY" ]; then
	echo "Using the existing key $KEY"
else
	openssl rand -hex 24 | tr -d '\n' > "$PASS"
	"$KEYTOOL" -genkeypair -keystore "$KEY" -storetype PKCS12 -storepass:file "$PASS" \
		-alias slicendice-test -keyalg RSA -keysize 2048 -validity 10000 \
		-dname "CN=Slice n Dice Test,O=Slice n Dice,C=DE"
	echo "Created $KEY"
fi
base64 -w0 "$KEY" | gh secret set TEST_KEYSTORE_B64
gh secret set TEST_KEYSTORE_PASSWORD < "$PASS"
echo "Secrets stored. The repository now has:"
gh secret list
