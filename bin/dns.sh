#!/usr/bin/env bash
# Check the in-network resolver: can a container reach the platform under the
# hostnames students actually use?
#
# This is the question the offline stack turns on. Traefik can only be
# addressed by the hostname its routers match on, and the catcher hands every
# student their own salt subdomain — an unbounded set that no `aliases:` list
# can cover. Without the `dns` service those names resolve to 127.0.0.1 inside
# the container (i.e. the container itself), and the OIDC SP's server-side
# discovery fetch of `https://<salt>.${ATTACKER_HOST}/.well-known/openid-configuration`
# dies on a connection error — taking the mIdP family (ids-1..ids-4) with it,
# along with out-of-band XXE/SSRF exfiltration from xml-sec, soap-sec,
# json-sec and rest-api-sec.
#
# Probes run INSIDE a real service container, never in a throwaway
# `run --network …` one: a throwaway does not inherit a compose service's
# `dns:` setting, so it would report the resolver as broken (or, worse, as
# working) for the wrong reason.
#
# Read-only. Needs no root.
set -euo pipefail

cd "$(dirname "$0")/.."

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
bad()  { printf '    \033[31m✗ %s\033[0m\n' "$*" >&2; }
good() { printf '    \033[32m✓ %s\033[0m\n' "$*"; }

set -a; . ./.env; set +a
: "${ATTACKER_HOST:?}" "${PORT_HTTPS:?}"

rc=0

say "Resolver"
if ./bin/compose ps --status running --services 2>/dev/null | grep -qx dns; then
    good "the dns service is running"
else
    bad "no dns container is running — 'just up' first"
    exit 1
fi

# Probe from the all-in-one (the service whose fetches motivated the
# resolver); fall back to the catcher if it is not up.
PROBE=app
./bin/compose ps --status running --services 2>/dev/null | grep -qx app || PROBE=catcher
info "probing from the '${PROBE}' container"

TRAEFIK_IP=$(./bin/compose exec -T "$PROBE" getent ahostsv4 traefik 2>/dev/null | awk '{print $1; exit}' || true)

# A salt nobody has ever created: the point is that the resolver answers for
# names that are on no list, so testing a known one would prove nothing.
SALT="zz$(date +%s)"

probe() {  # probe <name> <traefik|elsewhere>
    local name="$1" kind="$2" out
    out=$(./bin/compose exec -T "$PROBE" getent ahostsv4 "$name" 2>/dev/null | awk '{print $1; exit}' || true)
    if [ -z "$out" ]; then bad "${name} does not resolve"; rc=1; return; fi
    case "$kind" in
        traefik)
            if [ "$out" = "$TRAEFIK_IP" ]; then
                good "${name} -> ${out} (traefik)"
            else
                bad "${name} -> ${out}, expected traefik at ${TRAEFIK_IP}"
                [ "$out" = "127.0.0.1" ] && info "127.0.0.1 = the probing container itself — the query never reached the resolver"
                rc=1
            fi ;;
        *)  good "${name} -> ${out}" ;;
    esac
}

say "Names, from inside the ${PROBE} container"
probe "${SALT}.${ATTACKER_HOST}" traefik   # the unbounded case: a brand-new salt
probe "${ATTACKER_HOST}"         traefik
probe "${HOST1}"                 traefik
probe "${IDP_HOST}"              traefik
probe traefik                    traefik   # service names must keep working
probe couchdb                    elsewhere
probe localhost                  elsewhere # bare localhost must stay loopback
probe example.com                elsewhere # and so must the rest of the internet

if [ "$(./bin/compose exec -T "$PROBE" getent ahostsv4 localhost 2>/dev/null | awk '{print $1; exit}')" != "127.0.0.1" ]; then
    bad "bare localhost is not loopback any more"
    rc=1
fi

say "Reachability"
if ./bin/compose exec -T "$PROBE" sh -c \
     "exec 3<>/dev/tcp/${SALT}.${ATTACKER_HOST}/${PORT_HTTPS}" >/dev/null 2>&1 \
   || ./bin/compose exec -T "$PROBE" sh -c \
     "echo | nc -w 5 ${SALT}.${ATTACKER_HOST} ${PORT_HTTPS}" >/dev/null 2>&1; then
    good "${PROBE} reaches ${SALT}.${ATTACKER_HOST}:${PORT_HTTPS}"
else
    bad "${PROBE} cannot reach ${SALT}.${ATTACKER_HOST}:${PORT_HTTPS}"
    info "The name resolves but the port does not answer — check traefik is up"
    info "and listening on ${PORT_HTTPS} inside its own netns."
    rc=1
fi

if [ "$rc" -ne 0 ]; then
    say "If this fails"
    info "./bin/compose logs dns"
    info "A crash loop on 'permission denied' reading the Corefile means the"
    info "bind mount lost its SELinux label, or the container is not running as"
    info "root — see the dns service in docker-compose.yml."
fi

exit $rc
