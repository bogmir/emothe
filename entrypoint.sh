#!/bin/sh
# Entrypoint script that runs migrations before starting the Phoenix app

set -e

echo "Running database migrations..."
/app/bin/playcode eval Playcode.Release.migrate

echo "Starting Phoenix application..."
exec /app/bin/playcode start
