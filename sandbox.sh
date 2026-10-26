#!/usr/bin/env bash

_SANENODE_IMAGE="docker.io/library/node:22-bookworm"

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

# 1. INSPECT: offline, read-only auditing.
inspectrepo() {
  _safenode_guard || return 1

  local -a cmd
  if (($#)); then
    cmd=("$@")
  else
    cmd=(/bin/bash)
  fi

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
    --entrypoint "${cmd[0]}" \
    "$_SANENODE_IMAGE" "${cmd[@]:1}"
}

# 2. DEVELOP: trusted project, writable working tree.
devnode() {
  _safenode_guard || return 1
  _require_node_project || return 1

  local mem="${DEV_MEM:-6g}"
  local cpus="${DEV_CPUS:-6}"
  local pids="${DEV_PIDS:-1024}"
  local -a cmd

  if (($#)); then
    cmd=("$@")
  else
    cmd=(/bin/bash)
  fi

  podman run --rm -it \
    --pull=never \
    --userns=keep-id \
    --cap-drop=all \
    --security-opt=no-new-privileges \
    --pids-limit="$pids" \
    --memory="$mem" \
    --cpus="$cpus" \
    -e HOME=/tmp \
    -e npm_config_cache=/tmp/.npm \
    -v "$(pwd -P):/app:rw" \
    -w /app \
    -p 127.0.0.1:3000:3000 \
    --entrypoint "${cmd[0]}" \
    "$_SANENODE_IMAGE" "${cmd[@]:1}"
}

# 3. TEST: network-enabled, disposable writable project copy.
testnode() {
  _safenode_guard || return 1
  _require_node_project || return 1

  local source workspace archive status
  source=$(pwd -P) || return 1

  workspace=$(mktemp -d "${TMPDIR:-/tmp}/podman-sandbox-test.XXXXXX") || {
    echo "ERROR: Could not create temporary workspace." >&2
    return 1
  }
  chmod 700 "$workspace"

  archive=$(mktemp "${TMPDIR:-/tmp}/podman-sandbox-archive.XXXXXX") || {
    rm -rf -- "$workspace"
    echo "ERROR: Could not create temporary archive." >&2
    return 1
  }

  # Exclude common local dependencies, Git metadata, and secrets.
  # The original working tree is never mounted into this container.
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
    rm -rf -- "$workspace"
    rm -f -- "$archive"
    return 1
  fi

  if ! tar -xf "$archive" -C "$workspace"; then
    echo "ERROR: Failed to extract project copy." >&2
    rm -rf -- "$workspace"
    rm -f -- "$archive"
    return 1
  fi

  rm -f -- "$archive"

  local -a cmd
  if (($#)); then
    cmd=("$@")
  else
    cmd=(/bin/bash)
  fi

  echo "Starting disposable test workspace."
  echo "Original repository: read-only and not mounted."
  echo "Temporary copy will be deleted on exit."

  # Capture failures without skipping cleanup under `set -e`.
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
      -p 127.0.0.1:3000:3000 \
      --entrypoint "${cmd[0]}" \
      "$_SANENODE_IMAGE" "${cmd[@]:1}"; then
    status=0
  else
    status=$?
  fi

  rm -rf -- "$workspace"
  return "$status"
}

# 4. UNTRUSTED: offline execution, read-only repository.
untrustednode() {
  _safenode_guard || return 1
  _require_node_project || return 1

  local -a cmd
  if (($#)); then
    cmd=("$@")
  else
    echo "Usage: untrustednode COMMAND [ARGUMENTS...]" >&2
    return 2
  fi

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
    --entrypoint "${cmd[0]}" \
    "$_SANENODE_IMAGE" "${cmd[@]:1}"
}
