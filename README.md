# eHacking — offline local setup

The all-in-one eHacking platform for **offline training laptops**: no internet,
a local CA (step-ca) instead of Let's Encrypt, and the modules baked into one
WildFly container to keep resource use low. CTF flags stay at their built-in
dummy values on purpose — every laptop is identical, so flags don't need to be
generated or rotated.

This is the deliberately-simpler sibling of the production `e-Hacking.de`
deployment (which uses Let's Encrypt + per-module containers). For local
*development* (building images, per-module work) use the main eHacking repo
instead.

## What runs

| Service        | Host                                   | Notes |
|----------------|----------------------------------------|-------|
| all-in-one     | `e-hacking.localhost`, `idp/sp/spa/rs/json/rest/soap/websec/xml.localhost` | root + OIDC + SAML + JSON + REST + SOAP + web + XML in one WildFly |
| catcher        | `attacker.localhost` (+ `*.attacker.localhost`) | attacker/exfil target & request inspector (replaces the old echo server) |
| victim-bot     | internal only                          | headless honest user (`oemmes`) for OIDC bot attacks |
| dns            | internal (`:53`)                       | in-network resolver: every platform hostname → Traefik |
| tls-init       | one-shot                               | mints the local CA + the single stack TLS cert at first start |
| ca-server      | `http://ca.localhost/root_ca.crt`      | plain-HTTP download of the CA root (to trust it) |
| traefik        | `:80` (→ HTTPS), `:443` (HTTPS)        | reverse proxy + TLS |
| couchdb        | internal                               | backend for the REST module |
| axis2-flag/fake| internal / `soap.localhost/axis2/...`  | SOAP WS-Addressing challenge |

## Prerequisites

A container runtime. **Rootless Podman is the default** (ships with Ubuntu, no
daemon, no root-equivalent `docker` group); Docker works as a fallback.

**One-time host setup for rootless Podman** (the Ansible provisioner does this
for you; do it by hand only when running standalone):

```bash
# let rootless containers publish ports 80/443
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-ehacking.conf
sudo sysctl --system
# expose the podman socket Traefik talks to, and keep it across logout
systemctl --user enable --now podman.socket
sudo loginctl enable-linger "$USER"
```

Docker needs no extra setup. Force a runtime with `RUNTIME=docker` /
`RUNTIME=podman` if auto-detection picks the wrong one.

The `*.localhost` hostnames must resolve to `127.0.0.1` **on the laptop**.
systemd-resolved does this automatically; otherwise add them to `/etc/hosts`.
Inside the compose network the same names resolve to Traefik instead — see
"In-network name resolution".

## Quickstart

```bash
just up          # or: ./start.sh
```

`up` is offline-safe and idempotent: it starts the whole stack and `tls-init`
mints the CA + server certificate on first run. It does **not** pull images
(the laptop has them pre-loaded).

Then trust the CA root once, in the browser and the system store:

```bash
curl -sSf http://ca.localhost/root_ca.crt -o ehacking-ca.crt
# import ehacking-ca.crt into the browser's "Authorities" / system trust store
```

Now browse `https://e-hacking.localhost/`.

## Common tasks

```bash
just            # list all recipes
just ps         # service status
just logs catcher
just dns        # check the in-network resolver (see below)
just down       # stop (CA state + volumes preserved)
just update     # ONLINE only: pull newer images, then restart
```

## TLS / certificates

No ACME, no CA server. The one-shot `tls-init` service creates a self-signed
root CA and signs a **single** leaf covering every public host plus
`attacker.localhost` and `*.attacker.localhost`; Traefik serves it through the
file provider (`traefik/dynamic/tls.yaml`). The root is published over plain
HTTP by `ca-server` (trusting a cert you cannot fetch yet is a chicken-and-egg
problem, so that one endpoint stays unencrypted) and imported into the SP's
JVM truststore at boot. `tls-init` is idempotent — it skips if the material is
already in the `ca` / `tls` volumes; to rotate, wipe both volumes and restart.

## In-network name resolution

Containers reach the platform through Traefik, and Traefik can only be
addressed by the hostname its routers match on. Compose can make a container
answer to extra names — that is what the `aliases:` list on the traefik
service used to do — but only to a **finite** list. The catcher hands every
student their own salt subdomain `<salt>.attacker.localhost`, an unbounded
set, so that list could never be complete.

Measured inside the all-in-one container before the `dns` service existed:

```
app -> getent ahostsv4 zz1.attacker.localhost    127.0.0.1   (the container itself)
app -> https://zz1.attacker.localhost/           TLS failure — that is WildFly, not Traefik
```

The `dns` service (CoreDNS, config in [dns/Corefile](dns/Corefile)) serves one
block per zone — `attacker.localhost`, handed in from `.env` so the hostname is
not written down twice, and `localhost` for everything else — rewrites every
name in them onto the service name `traefik`, and forwards the rest to the
runtime's own resolver. Service names (`traefik`, `catcher`, `couchdb`, …) and
internet names therefore keep working. Bare `localhost` keeps meaning loopback:
the rewrite rule requires at least one label in front of it.

The services that need it carry `dns: *dns` — `app`, `catcher` and
`victim-bot`. Adding a hostname under `*.localhost` needs no change anywhere.

Verify it, from inside a real service container, with a salt that has never
existed:

```bash
just dns
```

`DNS_RESOLVER_IP` in `.env` is pinned because a client can only name its
resolver by IP address, never by service name; it has to stay inside the
`ehacking` subnet at the bottom of `docker-compose.yml`. If that range
collides with something else on the laptop, change both together and
`just down && just up` so the network is recreated.

What breaks without it: the OIDC SP's server-side discovery fetch for the mIdP
challenges (ids-1…ids-4), and out-of-band XXE/SSRF exfiltration from xml-sec,
soap-sec, json-sec and rest-api-sec.

## Catcher

Open (passwordless) signup is enabled (`CATCHER_OPEN_SIGNUP=true`) — fine for a
single offline trainee. The instructor and superuser areas use the password
`student` (override via `CATCHER_INSTRUCTOR_PASSWORD` / `CATCHER_SUPERUSER_PASSWORD`).

## Notes

- **Catcher runs in single-user mode** (`CATCHER_SINGLE_USER=true`): one
  implicit instance on the bare `attacker.localhost`, no salt subdomain. It
  started as the workaround for salt subdomains being unroutable inside the
  compose network. Both blockers are gone now — `tls-init` signs a
  `*.attacker.localhost` wildcard SAN and the `dns` service resolves any salt
  — so `CATCHER_SINGLE_USER=false` gives the standard multi-tenant catcher.
  It stays `true` by default only because one trainee per laptop needs no
  per-student instances. Requires a catcher image that includes the
  `CATCHER_SINGLE_USER` feature.
- **`soap-sec`** historically failed to deploy in the all-in-one image (missing
  JAXB-API on the classpath); see the platform repo for the fix status. SOAP is
  the lowest-priority module here.
