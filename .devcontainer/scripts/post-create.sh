#!/usr/bin/env bash
# postCreateCommand: runs once inside the container after it's created.
set -euo pipefail

ROOT_DIR="$(pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/.devcontainer/scripts/lib/common.sh"

ensure_env GITHUB_REPO PROJECT_DIR_NAME COMPOSE_FILE_PATH

PROJECT_DIR="$ROOT_DIR/${PROJECT_DIR_NAME:-project}"
COMPOSE_FILE_PATH="${COMPOSE_FILE_PATH:-deployment/docker/docker-compose.yml}"

if ! gh auth status >/dev/null 2>&1; then
  log "Not authenticated with GitHub CLI yet - starting device login."
  log "Open the URL shown below and enter the one-time code when prompted."
  if ! gh auth login --hostname github.com --git-protocol https --web; then
    err "gh auth login did not complete."
    err "Run 'gh auth login' manually in a terminal, then re-run: bash .devcontainer/scripts/post-create.sh"
    exit 0
  fi
fi

if [ -z "${GITHUB_REPO:-}" ]; then
  warn "GITHUB_REPO is still not set - export it in your host shell profile or"
  warn "re-run this script from an interactive terminal so it can prompt you:"
  warn "  bash .devcontainer/scripts/post-create.sh"
  exit 0
fi

if [ -d "$PROJECT_DIR/.git" ]; then
  log "'$PROJECT_DIR' already cloned - pulling latest on the current branch."
  git -C "$PROJECT_DIR" pull --ff-only || warn "Pull failed - resolve manually in $PROJECT_DIR."
else
  log "Cloning $GITHUB_REPO into $PROJECT_DIR ..."
  gh repo clone "$GITHUB_REPO" "$PROJECT_DIR"
fi

git config --global --add safe.directory "$PROJECT_DIR"

log "Done."
log "Supporting services are defined in $PROJECT_DIR/$COMPOSE_FILE_PATH"
log "Bring them up with: docker compose -f $PROJECT_DIR/$COMPOSE_FILE_PATH up -d"
