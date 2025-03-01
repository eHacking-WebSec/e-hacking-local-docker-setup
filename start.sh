#!/bin/bash

set -e

cd /home/student/.hidden
docker compose down
docker compose pull
docker system prune -f
docker compose up
