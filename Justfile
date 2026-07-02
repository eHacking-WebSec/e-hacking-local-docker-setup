# eHacking offline-training stack — shortcuts. `just` lists recipes.
# Runtime-agnostic: bin/compose auto-selects podman (default) or docker.
# On the training laptop the stack also autostarts on login via a systemd
# user service (ehacking.service) — these recipes are for manual control.

set shell := ["bash", "-cu"]

default:
    @just --list --unsorted

# Materialise per-install CTF flags (idempotent — keeps existing values). Reads
# the dummy list from the local all-in-one image and randomises it into flags.env.
flags:
    ./bin/make-flags.sh

# Rotate ALL flag values to fresh tokens.
flags-rotate:
    ./bin/make-flags.sh --force

# Start the stack (detached, idempotent). Offline-safe: does NOT pull. Materialises
# flags first so the app gets real (randomised) values instead of the image dummies.
up:
    ./bin/make-flags.sh
    ./bin/compose up -d

# Stop the stack (containers only; volumes / CA state preserved).
down:
    ./bin/compose down

# Restart a single service, e.g. `just restart catcher`.
restart SERVICE:
    ./bin/compose up -d --force-recreate {{SERVICE}}

# Service status.
ps:
    ./bin/compose ps

# Tail logs, optionally for one service: `just logs catcher`.
logs SERVICE="":
    ./bin/compose logs -f {{SERVICE}}

# Open a shell in a service container: `just shell app` (the all-in-one),
# `just shell catcher`, … Falls back to sh when bash is absent.
shell SERVICE:
    ./bin/compose exec {{SERVICE}} bash || ./bin/compose exec {{SERVICE}} sh

# ONLINE only (provisioning): pull newer container images.
pull:
    ./bin/compose pull

# ONLINE only: bring everything to latest — repo (compose/config), images,
# then restart in place.
update:
    git pull --ff-only
    ./bin/compose pull
    ./bin/compose up -d

# Print the CA root cert download URL (import to trust the stack's TLS).
ca-cert:
    @echo "http://ca.localhost/root_ca.crt"
