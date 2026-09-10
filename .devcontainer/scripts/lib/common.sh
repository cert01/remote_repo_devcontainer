#!/usr/bin/env bash
# Shared helpers sourced by the other bootstrap scripts.

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[bootstrap][warn]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[bootstrap][error]\033[0m %s\n' "$*" >&2; }

# GITHUB_REPO / PROJECT_DIR_NAME / COMPOSE_FILE_PATH are normally supplied as
# real host env vars (see containerEnv in devcontainer.json + README). This
# file is the in-container fallback: it lives in the workspace volume, so it
# survives container rebuilds even though it's gitignored and never part of
# this repo's history.
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

# Sources $ENV_FILE into the current shell if it exists. No prompting.
load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
}

# Writes/updates NAME=VALUE in $ENV_FILE, replacing an existing line for NAME.
# Rewrites the file line-by-line in bash rather than via sed, so values
# containing "/", "&", etc. (e.g. org/repo, a compose file path) are safe.
set_env_var() {
  local name="$1" value="$2" tmp line found=0
  tmp="$(mktemp "${ENV_FILE}.XXXXXX")"
  if [ -f "$ENV_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" == "$name="* ]]; then
        printf '%s=%s\n' "$name" "$value" >>"$tmp"
        found=1
      else
        printf '%s\n' "$line" >>"$tmp"
      fi
    done <"$ENV_FILE"
  fi
  if [ "$found" -eq 0 ]; then
    printf '%s=%s\n' "$name" "$value" >>"$tmp"
  fi
  mv "$tmp" "$ENV_FILE"
}

# For each var name given: use it if already set in the environment (e.g.
# from containerEnv/localEnv), else fall back to $ENV_FILE, else prompt for
# it interactively and persist the answer to $ENV_FILE for next time.
ensure_env() {
  load_env
  local name current default
  for name in "$@"; do
    current="${!name:-}"
    if [ -n "$current" ]; then
      continue
    fi
    default=""
    case "$name" in
      PROJECT_DIR_NAME)  default="project" ;;
      COMPOSE_FILE_PATH) default="deployment/docker/docker-compose.yml" ;;
    esac
    if [ ! -t 0 ]; then
      warn "$name is not set and this shell isn't interactive - skipping prompt."
      continue
    fi
    if [ -n "$default" ]; then
      read -r -p "$(printf '[bootstrap] %s [%s]: ' "$name" "$default")" current
      current="${current:-$default}"
    else
      read -r -p "$(printf '[bootstrap] %s (required, e.g. org/repo): ' "$name")" current
    fi
    if [ -z "$current" ]; then
      err "$name is required."
      exit 1
    fi
    set_env_var "$name" "$current"
    export "$name=$current"
  done
}
