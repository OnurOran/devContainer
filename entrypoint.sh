#!/usr/bin/env bash
set -euo pipefail

# Gracefully stop dockerd on container stop/restart
cleanup() {
  local dockerd_pid
  dockerd_pid="$(cat /var/run/docker.pid 2>/dev/null)" || true
  if [ -n "$dockerd_pid" ]; then
    kill "$dockerd_pid" 2>/dev/null || true
    wait "$dockerd_pid" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup SIGTERM SIGINT

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

# Keep container alive (wait allows trap to fire, unlike tail -f)
while true; do sleep infinity & wait $!; done
