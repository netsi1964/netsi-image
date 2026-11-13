#!/bin/bash
# Creates (once) a local, self-signed code-signing identity for Netsi Image and
# makes it available to codesign. A stable identity means macOS remembers the
# app's access to the OpenRouter key in the Keychain, so every rebuild does not
# trigger a new "Netsi Image ønsker at…" prompt.
#
#   scripts/signing-identity.sh          # create the identity if missing
#   scripts/signing-identity.sh --print  # print the identity name

set -euo pipefail

IDENTITY_NAME="Netsi Image Local"
KEYCHAIN="$HOME/Library/Keychains/netsi-image-signing.keychain-db"
STATE_DIR="$HOME/Library/Application Support/dk.netsi.image/signing"
PASSWORD_FILE="$STATE_DIR/keychain-password"

if [[ "${1:-}" == "--print" ]]; then
  echo "$IDENTITY_NAME"
  exit 0
fi

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$IDENTITY_NAME\""; then
  echo "==> Signeringsidentitet findes: $IDENTITY_NAME"
else
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  if [[ ! -f "$PASSWORD_FILE" ]]; then
    openssl rand -hex 24 > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
  fi
  PASSWORD="$(cat "$PASSWORD_FILE")"

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  echo "==> Laver selvsigneret kode-signeringscertifikat"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -subj "/CN=$IDENTITY_NAME/O=Netsi/C=DK" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

  openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY_NAME" -out "$TMP/identity.p12" \
    -passout "pass:$PASSWORD" >/dev/null 2>&1

  if [[ -f "$KEYCHAIN" ]]; then
    security unlock-keychain -p "$PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 || true
  else
    security create-keychain -p "$PASSWORD" "$KEYCHAIN"
  fi
  security set-keychain-settings "$KEYCHAIN"          # ingen auto-lås
  security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"

  security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" \
    -T /usr/bin/codesign -A >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null

  # Sørg for at codesign kan finde nøglen uden at spørge.
  EXISTING="$(security list-keychains -d user | sed -e 's/^ *//' -e 's/"//g')"
  if ! echo "$EXISTING" | grep -q "netsi-image-signing.keychain"; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s $EXISTING "$KEYCHAIN"
  fi

  if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$IDENTITY_NAME\""; then
    echo "Fejl: identiteten kunne ikke oprettes." >&2
    exit 1
  fi
  echo "==> Signeringsidentitet oprettet: $IDENTITY_NAME"
fi

# Tillidsindstillinger: uden dem behandler macOS signaturen som ukendt og
# spørger igen ved hver adgang til Keychain. Kræver én godkendelse fra brugeren.
security find-certificate -c "$IDENTITY_NAME" -p "$KEYCHAIN" > "$STATE_DIR/cert.pem" 2>/dev/null || true
if [[ -s "$STATE_DIR/cert.pem" ]] && ! security verify-cert -c "$STATE_DIR/cert.pem" -p codeSign >/dev/null 2>&1; then
  echo "==> Certifikatet skal markeres som betroet (kræver én godkendelse)"
  if security add-trusted-cert -r trustRoot -p codeSign \
      -k "$HOME/Library/Keychains/login.keychain-db" "$STATE_DIR/cert.pem" >/dev/null 2>&1; then
    echo "==> Certifikatet er betroet til kodesignering"
  else
    echo "Advarsel: kunne ikke tilføje tillid automatisk." >&2
    echo "  Gør det i Nøgleadgang: '$IDENTITY_NAME' → Slå op → Tillid → Kodesignering: Tillad altid." >&2
  fi
fi
