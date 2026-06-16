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
| step-ca        | internal (`:9000`)                     | local CA issuing TLS certs via ACME |
| ca-server      | `http://ca.localhost/root_ca.crt`      | plain-HTTP download of the CA root (to trust it) |
| traefik        | `:80` (ACME/HTTP), `:443` (HTTPS)      | reverse proxy + TLS |
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

The `*.localhost` hostnames must resolve to `127.0.0.1`. systemd-resolved does
this automatically; otherwise add them to `/etc/hosts`.

## Quickstart

```bash
just up          # or: ./start.sh
```

`up` is offline-safe and idempotent: it starts the whole stack and step-ca
issues the TLS certs over ACME. It does **not** pull images (the laptop has
them pre-loaded).

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
just down       # stop (CA state + volumes preserved)
just update     # ONLINE only: pull newer images, then restart
```

## TLS / certificates

step-ca is the local root of trust. Traefik gets a **per-host** cert from it
over ACME (HTTP-01) for every public hostname — including the bare
`attacker.localhost` catcher host. Each hostname is wired as a docker `link` on
the step-ca service so the HTTP challenge routes back through Traefik. Because
the catcher runs single-user (one instance on the bare host, no salt
subdomains), there are no wildcard hostnames to cover — plain ACME is enough,
with no pre-issued cert or file provider.

## Catcher

Open (passwordless) signup is enabled (`CATCHER_OPEN_SIGNUP=true`) — fine for a
single offline trainee. The instructor and superuser areas use the password
`student` (override via `CATCHER_INSTRUCTOR_PASSWORD` / `CATCHER_SUPERUSER_PASSWORD`).

## Notes

- **Catcher runs in single-user mode** (`CATCHER_SINGLE_USER=true`): one
  implicit instance on the bare `attacker.localhost`, no salt subdomain. This is
  what makes the OIDC malicious-IdP flow work offline — there's no random
  `<salt>.attacker.localhost` to resolve, and the bare host gets a normal ACME
  cert. Standard multi-tenant salt mode is a production concern (it needs both a
  `*.attacker.localhost` wildcard cert and a wildcard DNS resolver for the
  compose network) and is intentionally not wired here — single-user is the
  offline default. Requires a catcher image that includes the
  `CATCHER_SINGLE_USER` feature.
- **`soap-sec`** historically failed to deploy in the all-in-one image (missing
  JAXB-API on the classpath); see the platform repo for the fix status. SOAP is
  the lowest-priority module here.
