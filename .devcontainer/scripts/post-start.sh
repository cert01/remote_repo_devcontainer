#!/usr/bin/env bash
# postStartCommand: runs every time the container starts.
set -euo pipefail

ROOT_DIR="$(pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/.devcontainer/scripts/lib/common.sh"

PROJECT_DIR="$ROOT_DIR/${PROJECT_DIR_NAME:-project}"

if ! gh auth status >/dev/null 2>&1; then
  warn "GitHub CLI is not authenticated. Run: gh auth login"
elif [ ! -d "$PROJECT_DIR/.git" ]; then
  warn "Project repo not cloned yet. Run: bash .devcontainer/scripts/post-create.sh"
fi

if docker info >/dev/null 2>&1; then
  if [ -n "${DOCKER_HOST:-}" ]; then
    log "Docker reachable at $DOCKER_HOST."
  else
    log "Docker reachable (local socket)."
  fi
else
  warn "Cannot reach the Docker daemon - check DOCKER_HOST, Docker Desktop, or the remote engine."
fi
