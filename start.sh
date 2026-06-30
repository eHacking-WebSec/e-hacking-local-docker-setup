#!/usr/bin/env bash
# Offline-safe bring-up of the eHacking training stack. Runtime-agnostic
# (podman-first via bin/compose) and idempotent. Does NOT pull or prune — the
# training laptop has its images pre-loaded and no internet. To refresh images
# while online (provisioning), run `just update` or `./bin/compose pull`.
#
# TLS is dead simple: tls-init mints a local CA + one server cert covering every
# host (incl. the catcher and its *.attacker.localhost salt subdomains); Traefik
# serves it via the file provider. No ACME, no CA server. Trust the CA root once
# (published at http://ca.localhost/root_ca.crt).
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Starting the stack…"
./bin/compose up -d

echo
echo "Up. Trust the CA root, then browse the modules over HTTPS:"
echo "  CA root:   http://ca.localhost/root_ca.crt"
echo "  Landing:   https://e-hacking.localhost/"
echo "  OIDC SP:   https://sp.localhost/oidc_sp/"
echo "  SAML SP:   https://sp.localhost/sp/"
echo "  Catcher:   https://attacker.localhost/"
