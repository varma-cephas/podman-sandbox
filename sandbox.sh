#!/usr/bin/env bash


if [[ -z "${_SANENODE_IMAGE:-}" ]]; then
  readonly _SANENODE_IMAGE="docker.io/library/node:22-bookworm"
fi

if [[ -z "${INSPECTIDE_PINNED_IMAGE:-}" ]]; then
  readonly INSPECTIDE_PINNED_IMAGE="docker.io/codercom/code-server:latest"
fi

# Validate Podman, image availability, and the current directory.
_safenode_guard() {
  if (( EUID == 0 )); then
    echo "ERROR: Refusing to run as host root." >&2
    return 1
  fi

  if ! command -v podman >/dev/null 2>&1; then
    echo "ERROR: Podman is not installed or not in PATH." >&2
    return 1
  fi

  if ! podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null |
       grep -qx true; then
    echo "ERROR: A working rootless Podman setup is required." >&2
    return 1
  fi

  local cwd home_real
  cwd=$(pwd -P) || return 1
  home_real=$(cd "$HOME" 2>/dev/null && pwd -P) || return 1

  if [[ "$cwd" == "/" || "$cwd" == "$home_real" ]]; then
    echo "ERROR: Refusing to mount root or your home directory." >&2
    return 1
  fi

  case "$cwd" in
    "$home_real"/.*)
      echo "ERROR: Refusing to mount a hidden home-directory path: $cwd" >&2
      return 1
      ;;
  esac

  if ! podman image exists "$_SANENODE_IMAGE" 2>/dev/null; then
    echo "ERROR: Required image is missing: $_SANENODE_IMAGE" >&2
    echo "Run: podman pull $_SANENODE_IMAGE" >&2
    return 1
  fi

  return 0
}

_require_node_project() {
  if [[ ! -f package.json ]]; then
    echo "ERROR: No package.json found in '$PWD'." >&2
    echo "Run this command from a Node.js project directory." >&2
    return 1
  fi
}

# Check the local Node.js image.
checknodeimg() {
  if podman image exists "$_SANENODE_IMAGE" 2>/dev/null; then
    printf '[OK] %s\n' "$_SANENODE_IMAGE"
    podman image inspect "$_SANENODE_IMAGE" \
      --format 'ID: {{.Id}} | Created: {{.Created}}' 2>/dev/null || true
    return 0
  fi

  printf '[MISSING] %s\n' "$_SANENODE_IMAGE" >&2
  printf 'Run: podman pull %s\n' "$_SANENODE_IMAGE" >&2
  return 1
}

# Check the local code-server image.
checkcodeimg() {
  if podman image exists "$INSPECTIDE_PINNED_IMAGE" 2>/dev/null; then
    printf '[OK] %s\n' "$INSPECTIDE_PINNED_IMAGE"
    podman image inspect "$INSPECTIDE_PINNED_IMAGE" \
      --format 'ID: {{.Id}} | Created: {{.Created}}' 2>/dev/null || true
    return 0
  fi

  printf '[MISSING] %s\n' "$INSPECTIDE_PINNED_IMAGE" >&2
  printf 'Run: podman pull %s\n' "$INSPECTIDE_PINNED_IMAGE" >&2
  return 1
}

# 1. INSPECT: offline, read-only auditing.
inspectrepo() {
  _safenode_guard || return 1

  if (($#)); then
    podman run --rm -it \
      --pull=never \
      --userns=keep-id \
      --network=none \
      --read-only \
      --cap-drop=all \
      --security-opt=no-new-privileges \
      --pids-limit=128 \
      --memory=1g \
      --cpus=2 \
      --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m \
      -v "$(pwd -P):/repo:ro" \
      -w /repo \
      --entrypoint "$1" \
      "$_SANENODE_IMAGE" "${@:2}"
  else
    podman run --rm -it \
      --pull=never \
      --userns=keep-id \
      --network=none \
      --read-only \
      --cap-drop=all \
      --security-opt=no-new-privileges \
      --pids-limit=128 \
      --memory=1g \
      --cpus=2 \
      --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m \
      -v "$(pwd -P):/repo:ro" \
      -w /repo \
      --entrypoint /bin/bash \
      "$_SANENODE_IMAGE"
  fi
}

# 2. DEVELOP: trusted project, writable working tree with persistent pnpm & corepack caches.
devnode() {
  _safenode_guard || return 1
  _require_node_project || return 1

  local mem="${DEV_MEM:-6g}"
  local cpus="${DEV_CPUS:-6}"
  local pids="${DEV_PIDS:-1024}"
  local repo

  repo="$(pwd -P)" || return 1

  # Ensure persistent named volumes exist for pnpm and corepack caching
  podman volume exists pnpm_store 2>/dev/null || podman volume create pnpm_store >/dev/null || return 1
  podman volume exists corepack_cache 2>/dev/null || podman volume create corepack_cache >/dev/null || return 1

  local -a tty_args=()
  local -a port_args=()

  if (($# == 0)); then
    tty_args=(-it)
    port_args=(-p 127.0.0.1:3001:3000)
  fi

  podman run --rm "${tty_args[@]}" \
    --pull=never \
    --userns=keep-id \
    --cap-drop=all \
    --security-opt=no-new-privileges \
    --pids-limit="$pids" \
    --memory="$mem" \
    --cpus="$cpus" \
    -e HOME=/tmp \
    -e npm_config_cache=/tmp/.npm \
    -e pnpm_config_store_dir=/tmp/.pnpm-store \
    -e COREPACK_HOME=/tmp/.corepack \
    -e COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    -v "$repo:/app:rw,z" \
    -v pnpm_store:/tmp/.pnpm-store:rw,z \
    -v corepack_cache:/tmp/.corepack:rw,z \
    -w /app \
    "${port_args[@]}" \
    --entrypoint /bin/bash \
    "$_SANENODE_IMAGE" \
    -c '
      mkdir -p /tmp/.local/bin || exit
      export PATH="/tmp/.local/bin:$PATH"
      corepack enable --install-directory /tmp/.local/bin || exit

      if (($#)); then
        exec "$@"
      else
        exec /bin/bash
      fi
    ' bash "$@"
}

# 3. TEST: network-enabled, disposable writable project copy (subshell isolated).
testnode() (
  _safenode_guard || return 1
  _require_node_project || return 1

  local source workspace archive status=0
  source=$(pwd -P) || return 1

  workspace=$(mktemp -d "${TMPDIR:-/tmp}/podman-sandbox-test.XXXXXX") || {
    echo "ERROR: Could not create temporary workspace." >&2
    return 1
  }
  chmod 700 "$workspace" || {
    rm -rf -- "$workspace"
    return 1
  }

  archive=$(mktemp "${TMPDIR:-/tmp}/podman-sandbox-archive.XXXXXX") || {
    rm -rf -- "$workspace"
    echo "ERROR: Could not create temporary archive." >&2
    return 1
  }

  cleanup_testnode() {
    rm -rf -- "$workspace" 2>/dev/null || true
    [[ -z "${archive:-}" ]] || rm -f -- "$archive" 2>/dev/null || true
  }

  trap cleanup_testnode EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  if ! tar -C "$source" \
      --exclude=.git \
      --exclude=node_modules \
      --exclude='.env*' \
      --exclude=.npmrc \
      --exclude=.ssh \
      --exclude=.aws \
      --exclude=.config \
      -cf "$archive" .; then
    echo "ERROR: Failed to prepare project copy." >&2
    return 1
  fi

  if ! tar -xf "$archive" -C "$workspace"; then
    echo "ERROR: Failed to extract project copy." >&2
    return 1
  fi

  rm -f -- "$archive" || return 1
  archive=""

  echo "Starting disposable test workspace."
  echo "Original repository: read-only and not mounted."
  echo "Temporary copy will be deleted on exit."

  local -a cmd
  if (($#)); then
    cmd=("$@")
  else
    cmd=(/bin/bash)
  fi

  if podman run --rm -it \
      --pull=never \
      --userns=keep-id \
      --cap-drop=all \
      --security-opt=no-new-privileges \
      --pids-limit="${TEST_PIDS:-256}" \
      --memory="${TEST_MEM:-2g}" \
      --cpus="${TEST_CPUS:-4}" \
      --tmpfs /tmp:rw,nosuid,nodev,size=512m \
      -e HOME=/tmp \
      -e npm_config_cache=/tmp/.npm \
      -v "$workspace:/app:rw" \
      -w /app \
      -p 127.0.0.1::3000 \
      --entrypoint "${cmd[0]}" \
      "$_SANENODE_IMAGE" "${cmd[@]:1}"; then
    status=0
  else
    status=$?
  fi

  return "$status"
)

# 4. UNTRUSTED: offline execution, read-only repository (requires explicit command).
untrustednode() {
  _safenode_guard || return 1
  _require_node_project || return 1

  if (($#)); then
    podman run --rm \
      --pull=never \
      --userns=keep-id \
      --network=none \
      --read-only \
      --cap-drop=all \
      --security-opt=no-new-privileges \
      --pids-limit=256 \
      --memory=1g \
      --cpus=2 \
      --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
      -e HOME=/tmp \
      -e npm_config_cache=/tmp/.npm \
      -v "$(pwd -P):/app:ro" \
      -w /app \
      --entrypoint "$1" \
      "$_SANENODE_IMAGE" "${@:2}"
  else
    echo "ERROR: untrustednode requires an explicit command." >&2
    echo "Usage: untrustednode COMMAND [ARGUMENTS...]" >&2
    return 2
  fi
}

# 5. INSPECT IDE: Browser-based code-server for safe repository auditing.
inspectide() {
  _safenode_guard || return 1
  checkcodeimg || return 1

  local repo cid host_port rc
  repo="$(pwd -P)" || return 1
  [[ -d "$repo" ]] || return 1

  cid=""

  cleanup_inspectide() {
    if [[ -n "$cid" ]]; then
      podman rm -f "$cid" >/dev/null 2>&1 || true
      cid=""
    fi
  }

  cid=$(podman run -d \
    --pull=never \
    --userns=keep-id \
    --cap-drop=all \
    --security-opt=no-new-privileges \
    --pids-limit=256 \
    --memory=2g \
    --cpus=2 \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=512m \
    -e HOME=/tmp \
    -e XDG_CONFIG_HOME=/tmp/.config \
    -e XDG_CACHE_HOME=/tmp/.cache \
    -e XDG_DATA_HOME=/tmp/.local/share \
    -v "$repo:/home/coder/project:ro,z" \
    -p 127.0.0.1::8080 \
    --entrypoint /usr/bin/code-server \
    "$INSPECTIDE_PINNED_IMAGE" \
    --disable-telemetry \
    --auth none \
    --bind-addr 0.0.0.0:8080 \
    /home/coder/project) || {
      echo "ERROR: Failed to start inspection container." >&2
      return 1
    }

  host_port=$(podman port "$cid" 8080/tcp 2>/dev/null |
    awk -F: 'NR == 1 {print $NF}')

  if [[ -z "$host_port" ]]; then
    echo "ERROR: Could not retrieve published port." >&2
    cleanup_inspectide
    return 1
  fi

  echo "InspectIDE started: http://127.0.0.1:${host_port}"
  echo "Stop with Ctrl+C."

  podman logs -f "$cid"
  rc=$?

  cleanup_inspectide
  return "$rc"
}

# ---------------------------------------------------------------------------
# Host Guardrails: Trap accidental host package manager execution
# ---------------------------------------------------------------------------
npm() {
  echo "ERROR: Host npm is disabled. Use 'devnode npm' or 'testnode' instead." >&2
  echo "       (To force raw host execution: command npm)" >&2
  return 1
}

pnpm() {
  echo "ERROR: Host pnpm is disabled. Use your container sandbox instead." >&2
  echo "       (To force raw host execution: command pnpm)" >&2
  return 1
}
