#!/usr/bin/env bash
# Detect the container runtime and emit eval-able shell assignments that the
# bin/compose wrapper (and start.sh) source. Podman-first: the offline
# training laptop runs rootless Podman by default (no daemon, ships in the
# Ubuntu archive, no root-equivalent docker group). Docker is the fallback.
#
# Emits: RUNTIME, COMPOSE_FILE, TRAEFIK_SOCK_MOUNT
#
# Overrides (env):
#   RUNTIME=docker|podman          force a runtime
#   CONTAINER_SOCKET=/path/to.sock force a specific socket
set -euo pipefail

emit() { printf '%s=%q\n' "$1" "$2"; }

have() { command -v "$1" >/dev/null 2>&1; }

# `podman compose` must be the compose-go wrapper (ships with podman 4.7+),
# NOT the legacy Python `podman-compose` (which collapses every service into a
# single pod and breaks Traefik's per-hostname routing).
podman_compose_ok() {
  have podman && podman compose version >/dev/null 2>&1
}

# --- pick the runtime ------------------------------------------------------
runtime="${RUNTIME:-}"
if [ -z "$runtime" ]; then
  if podman_compose_ok; then
    runtime=podman
  elif have docker && docker compose version >/dev/null 2>&1; then
    runtime=docker
  else
    echo "runtime-env: no usable runtime found. Install podman (>=4.7, with 'podman compose') or docker (with the compose v2 plugin)." >&2
    exit 1
  fi
fi

case "$runtime" in
  podman)
    # Locate the podman socket: rootless first (best), then rootful.
    socket="${CONTAINER_SOCKET:-}"
    if [ -z "$socket" ]; then
      if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/podman/podman.sock" ]; then
        socket="$XDG_RUNTIME_DIR/podman/podman.sock"
      elif [ -S /run/podman/podman.sock ]; then
        socket=/run/podman/podman.sock
      else
        echo "runtime-env: podman selected but no socket found." >&2
        echo "  rootless: systemctl --user enable --now podman.socket" >&2
        echo "  rootful:  sudo systemctl enable --now podman.socket" >&2
        exit 1
      fi
    fi
    emit RUNTIME podman
    emit COMPOSE_FILE "docker-compose.yml:compose.podman.yml"
    # Traefik (and the docker provider) talk to the socket as if it were
    # Docker's. :Z relabels for SELinux (harmless where SELinux is absent).
    emit TRAEFIK_SOCK_MOUNT "${socket}:/var/run/docker.sock:Z"
    ;;
  docker)
    socket="${CONTAINER_SOCKET:-/var/run/docker.sock}"
    emit RUNTIME docker
    emit COMPOSE_FILE "docker-compose.yml"
    emit TRAEFIK_SOCK_MOUNT "${socket}:/var/run/docker.sock"
    ;;
  *)
    echo "runtime-env: unknown RUNTIME='$runtime' (expected podman or docker)" >&2
    exit 1
    ;;
esac
