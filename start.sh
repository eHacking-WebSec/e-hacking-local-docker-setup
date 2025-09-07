#!/bin/bash
set -e

# determine docker compose command
if command -v docker &>/dev/null && docker --help | grep -q "compose"; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

# load .env if present
[ -f .env ] && set -o allexport && . .env && set +o allexport

# create attacker folder and index.php with phpinfo()
if [ -n "${ATTACKER_HOST:-}" ]; then
    TARGET="$HOME/$ATTACKER_HOST"
    mkdir -p "$TARGET"
    [ -f "$TARGET/index.php" ] || printf '%s\n' '<?php phpinfo(); ?>' > "$TARGET/index.php"
    chmod 777 "$TARGET" || true
    chmod 777 "$TARGET/index.php" || true
fi

cd "$HOME/.hidden"
$DOCKER_COMPOSE down
$DOCKER_COMPOSE pull
docker system prune -f
$DOCKER_COMPOSE up
