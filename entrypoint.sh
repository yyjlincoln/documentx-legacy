#!/bin/sh
set -e

# Write secrets.json from env var if provided
if [ -n "$SECRETS_JSON" ]; then
    echo "$SECRETS_JSON" > /app/backend/secrets.json
fi

exec "$@"
