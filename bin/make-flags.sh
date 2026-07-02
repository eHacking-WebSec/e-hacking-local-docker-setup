#!/usr/bin/env bash
# Deploy per-install CTF flags for the offline stack — the offline take on
# e-hacking.de's bin/make-flags.sh.
#
# The all-in-one image ships an aggregated *dummy* flag list at
# /etc/ehacking/flags.env (derived at build from the module images — no
# hand-maintained copy). We read that list from the LOCAL image, replace each
# `_dummy}` marker with a fresh random token, and write flags.env. The axis2-flag
# image contributes its one FLAG_ the same way.
#
# The REAL values are delivered to the containers ONLY via env_file (see
# docker-compose.yml) — never baked or mounted into an image — so a file-read
# attack (the XXE/LFI challenges) can't harvest them. The three file-based
# challenge flags (xxe/xslt) ARE files (that's their point) and are written here
# too, to be bind-mounted over the image's dummies.
#
#   ./bin/make-flags.sh          # top up: keep existing flags.env values, add new keys
#   ./bin/make-flags.sh --force  # rotate every value
#
# Offline-safe: reads images that are already present locally (no pull, no
# registry access). If the images aren't present yet it warns and leaves the
# env flags at their image dummies (file flags are still written).
set -euo pipefail
cd "$(dirname "$0")/.."

FORCE=0
case "${1:-}" in
  -f|--force) FORCE=1 ;;
  '') ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

# DOCKER_REGISTRY / VARIANT live in .env.
set -a; . ./.env; set +a
RT="${RUNTIME:-$(command -v podman >/dev/null 2>&1 && echo podman || echo docker)}"
AIO_IMAGE="${DOCKER_REGISTRY}/ehacking:${VARIANT}"
AXIS2_IMAGE="${DOCKER_REGISTRY}/axis2-flag:latest"
OUT=flags.env

rnd() { ( set +o pipefail; tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16 ); }

# --- collect the dummy FLAG_ list from the local images --------------------
dummies=""
if d=$("$RT" run --rm --entrypoint cat "$AIO_IMAGE" /etc/ehacking/flags.env 2>/dev/null); then
  dummies+="$d"$'\n'
else
  echo "warn: could not read $AIO_IMAGE:/etc/ehacking/flags.env (image present?) — env flags left at image dummies" >&2
fi
if a=$("$RT" run --rm --entrypoint env "$AXIS2_IMAGE" 2>/dev/null | grep '^FLAG_'); then
  dummies+="$a"$'\n'
fi
dummies=$(printf '%s' "$dummies" | grep '^FLAG_' | sort -u || true)

if [ -z "$dummies" ]; then
  # Images unreadable (e.g. offline before the first pull) — never clobber an
  # existing flags.env; leave env flags to the image dummies if there's none yet.
  if [ -e "$OUT" ]; then echo "warn: flag images unreadable — keeping existing $OUT" >&2
  else echo "warn: no flag sources and no existing $OUT — env flags left to image dummies" >&2; fi
else
  # Top-up: preserve existing real values, only mint new/rotated ones.
  declare -A existing=()
  if [ -e "$OUT" ]; then
    while IFS= read -r l || [ -n "$l" ]; do
      [[ -z "$l" || "$l" =~ ^[[:space:]]*# ]] && continue
      [[ "$l" == *=* ]] || continue
      existing["${l%%=*}"]="${l#*=}"
    done < "$OUT"
  fi
  umask 077
  printf '# CTF flags — generated %s. Rotate: ./bin/make-flags.sh --force\n\n' "$(date)" > "$OUT"
  added=0 kept=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%=*}"; val="${line#*=}"
    if [ "$FORCE" -eq 0 ] && [ -n "${existing[$key]:-}" ]; then
      new="${existing[$key]}"; kept=$((kept+1))
    else
      new=$(printf '%s' "$val" | sed "s/_dummy}$/_$(rnd)}/"); added=$((added+1))
    fi
    printf '%s=%s\n' "$key" "$new" >> "$OUT"
  done <<< "$dummies"
  echo "wrote $OUT (minted=$added kept=$kept)" >&2
fi

# --- file-based challenge flags (xxe/xslt) — individual read targets --------
gen_file() {
  local path="$1" content="$2"
  # Keep an existing REAL file (top-up). Replace a leftover mount-created directory
  # (podman turns a missing bind source into a dir) or rotate on --force.
  if [ -f "$path" ] && [ "$FORCE" -eq 0 ]; then echo "keep $path" >&2; return; fi
  rm -rf "$path"
  printf '%b' "$content" > "$path"
  # World-readable: the containerised challenge (jboss) reads these via bind-mount.
  chmod 0644 "$path"
  echo "wrote $path" >&2
}
gen_file flag_xslt1.xml "<flag>FLAG{xslt_1_$(rnd)}</flag>"
gen_file flag_xxe1.txt  "FLAG{xxe_1_$(rnd)}"
# xxe2 line 1 carries < " ' — XML metacharacters the XXE challenge must survive.
gen_file flag_xxe2.txt  "< \" '\nFLAG{xxe_2_$(rnd)}"

echo "Done." >&2
