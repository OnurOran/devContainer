#!/usr/bin/env bash
set -euo pipefail

mkdir -p /home/developer
chown -R developer:developer /home/developer

# Start dockerd (DinD)
mkdir -p /var/lib/docker
dockerd >/var/log/dockerd.log 2>&1 &

# Wait for docker to be ready
for i in {1..60}; do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: dockerd did not start. Check /var/log/dockerd.log" >&2
  tail -n 200 /var/log/dockerd.log >&2 || true
  exit 1
fi

echo "dockerd is up."

# Keep container alive
tail -f /dev/null
