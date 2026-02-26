#!/bin/sh
# Entrypoint script that runs migrations before starting the Phoenix app

set -e

echo "Running database migrations..."
/app/bin/emothe eval Emothe.Release.migrate

echo "Starting Phoenix application..."
exec /app/bin/emothe start
