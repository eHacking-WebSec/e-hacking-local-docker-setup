#!/bin/bash

set -e

# Bestimme den korrekten Docker Compose Befehl
if command -v docker &> /dev/null && docker --help | grep -q "compose"; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

cd $HOME/.hidden
$DOCKER_COMPOSE down
$DOCKER_COMPOSE pull
docker system prune -f
$DOCKER_COMPOSE up
