#!/usr/bin/env bash
set -euo pipefail

umask 077

INSTALL_DIR="${HOME}/.config/podman-sandbox"
SCRIPT_SOURCE="./podman-sandbox.sh"
TARGET="${INSTALL_DIR}/sandbox.sh"

# 1. Determine the supported interactive shell.
case "${SHELL##*/}" in
  bash) RC_FILE="${HOME}/.bashrc" ;;
  zsh)  RC_FILE="${HOME}/.zshrc" ;;
  *)
    echo "ERROR: Only Bash and Zsh are supported." >&2
    echo "Detected SHELL: ${SHELL:-unset}" >&2
    exit 1
    ;;
esac

# 2. Validate the source before modifying the installation.
if [[ ! -f "$SCRIPT_SOURCE" ]]; then
  echo "ERROR: '$SCRIPT_SOURCE' not found." >&2
  echo "Run this installer from the repository root." >&2
  exit 1
fi

echo "Validating $SCRIPT_SOURCE..."
bash -n "$SCRIPT_SOURCE"

# 3. Create a private installation directory.
install -d -m 700 "$INSTALL_DIR"

# 4. Stage and validate the replacement before installing it.
TEMP_FILE=$(mktemp "${INSTALL_DIR}/.sandbox.sh.XXXXXX")
trap 'rm -f "${TEMP_FILE:-}"' EXIT

install -m 600 "$SCRIPT_SOURCE" "$TEMP_FILE"
bash -n "$TEMP_FILE"

# Rename within the same directory to avoid a partially copied library.
mv -f "$TEMP_FILE" "$TARGET"
TEMP_FILE=""

echo "Installed: $TARGET"

# 5. Configure the interactive shell only if necessary.
EXACT_SOURCE_LINE='source "$HOME/.config/podman-sandbox/sandbox.sh"'

touch "$RC_FILE"

if grep -Fqx "$EXACT_SOURCE_LINE" "$RC_FILE"; then
  echo "Shell configuration already contains the source line."
else
  BACKUP_FILE="${RC_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
  cp -p "$RC_FILE" "$BACKUP_FILE"
  echo "Backup created: $BACKUP_FILE"

  printf '\n# Podman Node.js sandbox helpers\n%s\n' \
    "$EXACT_SOURCE_LINE" >> "$RC_FILE"

  echo "Configured: $RC_FILE"
fi

echo
echo "Installation complete."
echo "Reload your shell with: source \"$RC_FILE\""
echo "Check the image with:    checknodeimg"
