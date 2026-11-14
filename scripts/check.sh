#!/usr/bin/env sh
# Health + credentials check from any machine with curl and openssl.
#   ./scripts/check.sh rtc.1venue.live                       -> signalling up?
#   ./scripts/check.sh http://127.0.0.1:7880 KEY SECRET           -> on the server itself
#   ./scripts/check.sh rtc.1venue.live APIkey secret          -> also proves the key/secret pair works
set -eu
DOMAIN="${1:?usage: check.sh <livekit-domain> [api-key api-secret]}"
case "$DOMAIN" in http://*|https://*) BASE="${DOMAIN%/}" ;; *) BASE="https://$DOMAIN" ;; esac
printf 'Signalling  %s/ ... ' "$BASE"
BODY="$(curl -fsS --max-time 8 "$BASE/" || true)"
[ "$BODY" = "OK" ] && echo "OK" || { echo "FAILED (got: ${BODY:-no response}). Check DNS and the Coolify domain (port 7880)."; exit 1; }
[ $# -ge 3 ] || exit 0
KEY="$2"; SECRET="$3"
b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
NOW=$(date +%s)
HEADER=$(printf '{"alg":"HS256","typ":"JWT"}' | b64)
PAYLOAD=$(printf '{"iss":"%s","sub":"health-check","nbf":%s,"exp":%s,"video":{"roomJoin":true,"room":"health-check"}}' "$KEY" "$NOW" "$((NOW + 300))" | b64)
SIG=$(printf '%s.%s' "$HEADER" "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" -binary | b64)
printf 'Credentials %s ... ' "$KEY"
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$BASE/rtc/validate?access_token=$HEADER.$PAYLOAD.$SIG")
[ "$CODE" = "200" ] && echo "accepted" || { echo "rejected (HTTP $CODE). The pair must be listed in LIVEKIT_KEYS."; exit 1; }
echo "Media (UDP/TCP/TURN) can only be tested from a browser: https://livekit.io/connection-test"
