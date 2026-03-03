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

Commands:
  build        Build image
  create       Create container (don't start)
  up           Start an existing stopped container
  bash         Exec into running container
  stop         Stop container
  rm           Remove container (keeps volumes)
  rebuild      Remove container + build image + recreate (keeps volumes)
  nuke         Remove container + volumes (DANGEROUS)
  status       Show status

Examples:
  ./dev.sh --name dev-alice create
  ./dev.sh --name dev-alice up
  ./dev.sh --name dev-alice bash
  ./dev.sh --name dev-bob --memory 4g --cpus 2 create
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

cmd_create() {
  if exists_container; then
    echo "Error: Container '$NAME' already exists." >&2
    exit 1
  fi

  ensure_image

  docker volume inspect "$HOME_VOL" >/dev/null 2>&1 || docker volume create "$HOME_VOL" >/dev/null
  docker volume inspect "$DIND_VOL" >/dev/null 2>&1 || docker volume create "$DIND_VOL" >/dev/null
  docker volume inspect "$LOCAL_VOL" >/dev/null 2>&1 || docker volume create "$LOCAL_VOL" >/dev/null

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
}

cmd_up() {
  if ! exists_container; then
    echo "Error: Container '$NAME' not found. Run './dev.sh create' first." >&2
    exit 1
  fi
  if running_container; then
    echo "Container '$NAME' is already running."
    return
  fi
  docker start "$NAME" >/dev/null
}

cmd_bash() {
  if ! running_container; then
    echo "Error: Container '$NAME' is not running. Run './dev.sh up' first." >&2
    exit 1
  fi
  exec_shell
}

cmd_stop() { docker stop "$NAME" >/dev/null 2>&1 || true; }

cmd_rm() {
  cmd_stop
  docker rm "$NAME" >/dev/null 2>&1 || true
}

cmd_rebuild() {
  cmd_rm
  cmd_build
  docker volume rm "$LOCAL_VOL" >/dev/null 2>&1 || true
  cmd_create
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
  "")       usage; exit 0 ;;
  build)    cmd_build ;;
  create)   cmd_create ;;
  up)       cmd_up ;;
  bash)     cmd_bash ;;
  stop)     cmd_stop ;;
  rm)       cmd_rm ;;
  rebuild)  cmd_rebuild ;;
  nuke)     cmd_nuke ;;
  status)   cmd_status ;;
  *) echo "Error: unknown command: $CMD" >&2; usage; exit 1 ;;
esac
