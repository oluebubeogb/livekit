#!/usr/bin/env sh
# Generate one LiveKit API key + secret for an app (run once per app that will use this server).
#   ./scripts/generate-keys.sh            -> prints a key, a secret and the LIVEKIT_KEYS entry
# Same result with Docker:  docker run --rm livekit/livekit-server:v1.13.11 generate-keys
set -eu
rand() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; }
KEY="API$(rand 12)"
SECRET="$(rand 43)"
echo "API Key:     $KEY"
echo "API Secret:  $SECRET"
echo
echo "Add to LIVEKIT_KEYS on the LiveKit resource:   $KEY: $SECRET"
echo "Give the app:  LIVEKIT_API_KEY=$KEY  LIVEKIT_API_SECRET=$SECRET"
