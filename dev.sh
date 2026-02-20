#!/usr/bin/env bash
set -euo pipefail

# Resolve script directory (works even when called from another path)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Defaults
NAME="devmachine"
IMAGE="devmachine:local"
MEMORY=""
CPUS=""

usage() {
  cat <<EOF
Usage: ./dev.sh [options] [cmd]

Options:
  --name NAME      Container name (default: devmachine)
  --memory MEM     Memory limit (e.g., 4g, 512m)
  --cpus NUM       CPU limit (e.g., 2, 0.5)

Default (no cmd): smart enter
  - if container doesn't exist: create + start + exec developer shell
  - if exists but stopped:      start + exec developer shell
  - if running:                 exec developer shell

Commands:
  build        Build image
  rebuild      Remove container + build image + up (keeps volumes, resets /usr/local)
  dev          Smart enter (same as default)
  up           Create+start (or start if exists), then exec developer shell
  in           Exec into running container, or up if not running
  stop         Stop container
  rm           Remove container (keeps volumes)
  nuke         Remove container + volumes (DANGEROUS)
  status       Show status

Examples:
  ./dev.sh                              # Default devmachine
  ./dev.sh --name dev-alice dev         # Replica for alice
  ./dev.sh --name dev-bob --memory 4g --cpus 2 up
  ./dev.sh --name dev-alice stop
  ./dev.sh --name dev-alice nuke
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)   [[ -z "${2:-}" ]] && { echo "Error: --name requires a value" >&2; exit 1; }; NAME="$2"; shift 2 ;;
    --memory) [[ -z "${2:-}" ]] && { echo "Error: --memory requires a value" >&2; exit 1; }; MEMORY="$2"; shift 2 ;;
    --cpus)   [[ -z "${2:-}" ]] && { echo "Error: --cpus requires a value" >&2; exit 1; }; CPUS="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "Error: unknown option: $1" >&2; usage; exit 1 ;;
    *) break ;;
  esac
done

CMD="${1:-}"

# Derive volume names from container name
HOME_VOL="${NAME}-home"
DIND_VOL="${NAME}-dind"
LOCAL_VOL="${NAME}-local"

exists_container() { docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; }
running_container() { docker ps --format '{{.Names}}' | grep -qx "$NAME"; }

ensure_image() {
  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Image '$IMAGE' not found, building..."
    cmd_build
  fi
}

cmd_build() {
  docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
}

exec_shell() {
  docker exec -it --user developer --workdir /home/developer "$NAME" bash -l
}

cmd_up() {
  ensure_image

  docker volume inspect "$HOME_VOL" >/dev/null 2>&1 || docker volume create "$HOME_VOL" >/dev/null
  docker volume inspect "$DIND_VOL" >/dev/null 2>&1 || docker volume create "$DIND_VOL" >/dev/null
  docker volume inspect "$LOCAL_VOL" >/dev/null 2>&1 || docker volume create "$LOCAL_VOL" >/dev/null

  if ! exists_container; then
    local run_args=(
      -d
      --name "$NAME"
      --privileged
      --network host
      --restart unless-stopped
      -e TERM="${TERM:-xterm-256color}"
      -v "$HOME_VOL":/home/developer
      -v "$DIND_VOL":/var/lib/docker
      -v "$LOCAL_VOL":/usr/local
    )

    [[ -n "$MEMORY" ]] && run_args+=(--memory "$MEMORY")
    [[ -n "$CPUS" ]]   && run_args+=(--cpus "$CPUS")

    docker run "${run_args[@]}" "$IMAGE" >/dev/null
  else
    if ! running_container; then
      docker start "$NAME" >/dev/null
    fi
  fi

  exec_shell
}

cmd_in() {
  if running_container; then
    exec_shell
  else
    cmd_up
  fi
}

cmd_dev() {
  cmd_up
}

cmd_stop() { docker stop "$NAME" >/dev/null 2>&1 || true; }

cmd_rm() {
  cmd_stop
  docker rm "$NAME" >/dev/null 2>&1 || true
}

cmd_rebuild() {
  cmd_rm
  cmd_build
  # Reset /usr/local volume so Docker re-populates from new image
  docker volume rm "$LOCAL_VOL" >/dev/null 2>&1 || true
  cmd_up
}

cmd_nuke() {
  echo "This will permanently delete container '$NAME' and ALL its volumes:"
  echo "  - $HOME_VOL (home directory)"
  echo "  - $DIND_VOL (docker data)"
  echo "  - $LOCAL_VOL (installed tools)"
  read -rp "Are you sure? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

  cmd_rm
  docker volume rm "$HOME_VOL" >/dev/null 2>&1 || true
  docker volume rm "$DIND_VOL" >/dev/null 2>&1 || true
  docker volume rm "$LOCAL_VOL" >/dev/null 2>&1 || true
}

cmd_status() {
  echo "== Container =="
  docker ps -a --filter "name=^/${NAME}$" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
  echo
  echo "== Volumes =="
  docker volume ls --filter "name=^${HOME_VOL}$|^${DIND_VOL}$|^${LOCAL_VOL}$" --format "table {{.Name}}\t{{.Driver}}"
}

case "$CMD" in
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
