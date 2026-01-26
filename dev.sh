#!/usr/bin/env bash
set -euo pipefail

NAME="devmachine"
IMAGE="devmachine:local"
HOME_VOL="devmachine-home"
DIND_VOL="devmachine-dind"   # DinD image/cache kalıcı olsun istersen; istemezsen kaldırabilirsin.

usage() {
  cat <<EOF
Usage: ./dev.sh [cmd]

Default (no cmd): smart enter
  - if container doesn't exist: create + attach
  - if exists but stopped:      start + attach
  - if running:                exec a new shell

Commands:
  build        Build image
  rebuild      Remove container + build image + up (keeps volumes)
  dev          Smart enter (same as default)
  up           Create+start (or start if exists) and attach
  in           Exec into running container, or up if not running
  stop         Stop container
  rm           Remove container (keeps volumes)
  nuke         Remove container + volumes (DANGEROUS)
  status       Show status
EOF
}

exists_container() { docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; }
running_container() { docker ps --format '{{.Names}}' | grep -qx "$NAME"; }

cmd_build() {
  docker build -t "$IMAGE" -f ./Dockerfile .
}

cmd_up() {
  docker volume inspect "$HOME_VOL" >/dev/null 2>&1 || docker volume create "$HOME_VOL" >/dev/null
  docker volume inspect "$DIND_VOL" >/dev/null 2>&1 || docker volume create "$DIND_VOL" >/dev/null

  if ! exists_container; then
    docker run -it \
      --name "$NAME" \
      --hostname "$NAME" \
      --privileged \
      --add-host=host.docker.internal:host-gateway \
      -e TERM="${TERM:-xterm-256color}" \
      -v "$HOME_VOL":/home/developer \
      -v "$DIND_VOL":/var/lib/docker \
      "$IMAGE"
  else
    docker start -ai "$NAME"
  fi
}

cmd_in() {
  if running_container; then
    docker exec -it "$NAME" bash
  else
    cmd_up
  fi
}

cmd_dev() {
  if exists_container; then
    if running_container; then
      docker exec -it "$NAME" bash
    else
      docker start -ai "$NAME"
    fi
  else
    cmd_up
  fi
}

cmd_stop() { docker stop "$NAME" >/dev/null 2>&1 || true; }

cmd_rm() {
  cmd_stop
  docker rm "$NAME" >/dev/null 2>&1 || true
}

cmd_rebuild() {
  cmd_rm
  cmd_build
  cmd_up
}

cmd_nuke() {
  cmd_rm
  docker volume rm "$HOME_VOL" >/dev/null 2>&1 || true
  docker volume rm "$DIND_VOL" >/dev/null 2>&1 || true
}

cmd_status() {
  echo "== Container =="
  docker ps -a --filter "name=^/${NAME}$" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
  echo
  echo "== Volumes =="
  docker volume ls --filter "name=^${HOME_VOL}$|^${DIND_VOL}$" --format "table {{.Name}}\t{{.Driver}}"
}

case "${1:-}" in
  ""|dev)   cmd_dev ;;
  build)    cmd_build ;;
  rebuild)  cmd_rebuild ;;
  up)       cmd_up ;;
  in)       cmd_in ;;
  stop)     cmd_stop ;;
  rm)       cmd_rm ;;
  nuke)     cmd_nuke ;;
  status)   cmd_status ;;
  *) usage; exit 1 ;;
esac
