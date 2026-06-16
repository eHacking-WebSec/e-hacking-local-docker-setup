#!/usr/bin/env bash
# Offline-safe bring-up of the eHacking training stack. Runtime-agnostic
# (podman-first via bin/compose) and idempotent. Does NOT pull or prune — the
# training laptop has its images pre-loaded and no internet. To refresh images
# while online (provisioning), run `just update` or `./bin/compose pull`.
#
# TLS is fully ACME: step-ca issues a per-host cert for every public hostname
# (incl. the bare attacker.localhost catcher host). No pre-issued wildcard /
# cert-ordering dance — the catcher is single-user, so there are no salt
# subdomains to cover.
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
