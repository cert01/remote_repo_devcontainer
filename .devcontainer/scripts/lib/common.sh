#!/usr/bin/env bash
# Shared helpers sourced by the other bootstrap scripts.

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[bootstrap][warn]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[bootstrap][error]\033[0m %s\n' "$*" >&2; }
