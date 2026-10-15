#!/bin/bash
# Build, sign, install to ~/Applications, launch. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"
id=mac-fancy-zones-dev app=build/mac-fancy-zones.app

# One-time: stable self-signed identity, so the Accessibility grant survives rebuilds (ad-hoc signatures don't).
if ! security find-identity -p codesigning | grep -q "$id"; then
    t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
    printf '[req]\ndistinguished_name=d\nx509_extensions=e\nprompt=no\n[d]\nCN=%s\n[e]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' "$id" > "$t/cnf"
    # System LibreSSL on purpose: Homebrew OpenSSL 3 writes .p12 files macOS rejects.
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$t/k" -out "$t/c" -days 3650 -config "$t/cnf" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$t/k" -in "$t/c" -out "$t/p" -passout pass:x
    security import "$t/p" -k ~/Library/Keychains/login.keychain-db -P x -T /usr/bin/codesign
fi

swift build -c release --product MacFancyZones
rm -rf "$app" && mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/MacFancyZones" "$app/Contents/MacOS/mac-fancy-zones"
cp Info.plist "$app/Contents/"
codesign --force --sign "$id" "$app"

pkill -x mac-fancy-zones || true
mkdir -p ~/Applications && rm -rf ~/Applications/mac-fancy-zones.app && cp -R "$app" ~/Applications/
open ~/Applications/mac-fancy-zones.app
echo "Installed ~/Applications/mac-fancy-zones.app. First run: grant Accessibility, then relaunch."
