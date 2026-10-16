#!/usr/bin/env bash
#
# Deploy CareCoins to the production server over SSH.
#
#   ./scripts/deploy.sh --dry-run     # print every step, change nothing
#   ./scripts/deploy.sh               # deploy, asking before the irreversible part
#   ./scripts/deploy.sh --yes         # deploy without the prompt (CI, or a repeat run)
#   ./scripts/deploy.sh --admin       # include the operator console (admin compose profile)
#   ./scripts/deploy.sh --reset-db    # DESTRUCTIVE: wipe the database and start empty
#
# Configuration lives in scripts/deploy.env (gitignored). Copy the .example and
# fill it in. See docs/deployment-and-delivery.md §2.
#
# What it does, in order:
#   1. Refuses to start unless the local tree is clean and pushed, so what runs
#      on the server is a commit you can actually point at.
#   2. Backs up the database *and* the uploads directory before anything else.
#      db-init runs migrations on container start, so by the time compose is up
#      the schema has already moved.
#   3. Copies secrets that are deliberately not in git (includes admin secrets with --admin).
#   4. Fast-forwards the server to your commit and rebuilds.
#   5. Probes the public API (and operator console under --admin) to prove the new routes are live.
#
# It never prints the contents of a secret, and never force-pushes or resets
# anything on the server.
#
# --reset-db is the one exception, and it is deliberately awkward: it destroys
# every family, activity and coin balance on the server, cannot be undone, and
# is not what you want unless you mean it. It forces a backup, refuses to run
# alongside --skip-backup, and requires you to type the host name even with
# --yes. Wiping production is not something to automate.

set -euo pipefail

# ─── Locations ────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO_ROOT/scripts/deploy.env"

SECRETS=(
  "firebase-credentials.json"
  "backend/.env"
)

# ─── Options ──────────────────────────────────────────────────────────────────

DRY_RUN=false
ASSUME_YES=false
SKIP_BACKUP=false
SKIP_SECRETS=false
WITH_ADMIN=false
RESET_DB=false
RESET_UPLOADS=false

usage() {
  sed -n '2,/^set -euo pipefail/ { /^set -euo pipefail/d; s/^#//; s/^ //; p; }' "${BASH_SOURCE[0]}"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN=true ;;
    --yes|-y)       ASSUME_YES=true ;;
    --skip-backup)  SKIP_BACKUP=true ;;
    --no-secrets)   SKIP_SECRETS=true ;;
    --admin)        WITH_ADMIN=true ;;
    --reset-db)     RESET_DB=true ;;
    --reset-uploads) RESET_UPLOADS=true ;;
    -h|--help)      usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
  shift
done

if $WITH_ADMIN; then
  SECRETS+=(
    "backend/admin.env"
    "backend/admin-db.env"
    "backend/tunnel.env"
  )
  COMPOSE="docker compose --profile admin"
else
  COMPOSE="docker compose"
fi

if $RESET_DB && $SKIP_BACKUP; then
  echo "error: --reset-db with --skip-backup would destroy the data and keep no copy." >&2
  echo "       If you truly want that, take the backup yourself first and re-run." >&2
  exit 1
fi

# ─── Output helpers ───────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; OFF=$'\033[0m'
else
  BOLD=''; RED=''; GREEN=''; YELLOW=''; DIM=''; OFF=''
fi

step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$OFF"; }
ok()   { printf '    %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
warn() { printf '    %s!%s %s\n' "$YELLOW" "$OFF" "$1"; }
die()  { printf '\n%serror:%s %s\n' "$RED" "$OFF" "$1" >&2; exit 1; }

# Runs a command on the server, or prints it under --dry-run.
remote() {
  if $DRY_RUN; then
    printf '    %s[dry-run] ssh %s %s%s\n' "$DIM" "$DEPLOY_HOST" "$*" "$OFF"
  else
    # shellcheck disable=SC2029  # deliberate: the command is built locally
    ssh $DEPLOY_SSH_OPTS "$DEPLOY_HOST" "$@"
  fi
}

# Same, but always runs — for read-only checks that are safe under --dry-run.
remote_read() {
  # shellcheck disable=SC2029
  ssh $DEPLOY_SSH_OPTS "$DEPLOY_HOST" "$@"
}

# ─── Configuration ────────────────────────────────────────────────────────────

step "Configuration"

[[ -f "$CONFIG" ]] || die "missing $CONFIG
    Copy scripts/deploy.env.example to scripts/deploy.env and fill it in."

# shellcheck source=/dev/null
source "$CONFIG"

: "${DEPLOY_HOST:?DEPLOY_HOST is not set in scripts/deploy.env}"
: "${DEPLOY_PATH:?DEPLOY_PATH is not set in scripts/deploy.env}"
DEPLOY_SSH_OPTS="${DEPLOY_SSH_OPTS:-}"
DEPLOY_URL="${DEPLOY_URL:-https://mycarecoins.app}"
DEPLOY_ADMIN_URL="${DEPLOY_ADMIN_URL:-https://admin.mycarecoins.app}"
DEPLOY_BACKUP_DIR="${DEPLOY_BACKUP_DIR:-$DEPLOY_PATH/backups}"
DEPLOY_PG_USER="${DEPLOY_PG_USER:-carecoins}"
DEPLOY_PG_DB="${DEPLOY_PG_DB:-carecoins}"

ok "host        $DEPLOY_HOST"
ok "path        $DEPLOY_PATH"
ok "public url  $DEPLOY_URL"
$WITH_ADMIN && ok "admin url   $DEPLOY_ADMIN_URL"
$DRY_RUN && warn "DRY RUN — nothing on the server will change"

# ─── Local preflight ──────────────────────────────────────────────────────────

step "Local checks"

cd "$REPO_ROOT"

[[ -n "$(git status --porcelain)" ]] && die "working tree is not clean.
    Commit or stash first — the server deploys a commit, not your desk."
ok "working tree clean"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
LOCAL_SHA="$(git rev-parse HEAD)"

git fetch --quiet origin "$BRANCH" 2>/dev/null || warn "could not reach origin; using local refs"
if [[ -n "$(git log "origin/$BRANCH..HEAD" --oneline 2>/dev/null)" ]]; then
  die "HEAD is not pushed to origin/$BRANCH.
    The server pulls from origin, so it cannot deploy what only exists here."
fi
ok "$BRANCH is pushed ($(git rev-parse --short HEAD))"

for f in "${SECRETS[@]}"; do
  [[ -f "$REPO_ROOT/$f" ]] || die "missing local secret: $f
    It is gitignored by design; it has to exist here to be copied over."
done
ok "local secrets present (${#SECRETS[@]} files)"

if $WITH_ADMIN; then
  grep -q '^TUNNEL_TOKEN=.\+' "$REPO_ROOT/backend/tunnel.env" \
    || die "TUNNEL_TOKEN is empty in backend/tunnel.env"
  grep -q '^CF_ACCESS_AUD=.\+' "$REPO_ROOT/backend/admin.env" \
    || die "CF_ACCESS_AUD is empty in backend/admin.env"
  grep -q '^CF_ACCESS_TEAM_DOMAIN=.\+' "$REPO_ROOT/backend/admin.env" \
    || die "CF_ACCESS_TEAM_DOMAIN is empty in backend/admin.env"
  grep -q '^ADMIN_DB_PASSWORD=.\+' "$REPO_ROOT/backend/admin-db.env" \
    || die "ADMIN_DB_PASSWORD is empty in backend/admin-db.env"
  ok "admin secrets validated (required keys non-empty)"
fi

# ─── Remote preflight ─────────────────────────────────────────────────────────

step "Server checks"

# Separate "cannot connect" from "connected, but the path is wrong" — they have
# completely different fixes, and one error covering both sends you hunting in
# the wrong place.
if ! ssh $DEPLOY_SSH_OPTS -o BatchMode=yes -o ConnectTimeout=10 "$DEPLOY_HOST" true 2>/dev/null; then
  die "cannot reach $DEPLOY_HOST over SSH.
    Check DEPLOY_HOST in scripts/deploy.env, and that the key works:
      ssh $DEPLOY_SSH_OPTS $DEPLOY_HOST true
    (BatchMode is on here, so a passphrase prompt also fails — unlock the key first
    with ssh-add, or point IdentityFile at one that needs no passphrase.)"
fi
ok "SSH to $DEPLOY_HOST works"

remote_read "test -d '$DEPLOY_PATH/.git'" \
  || die "connected to $DEPLOY_HOST, but $DEPLOY_PATH is not a git checkout.
    Check DEPLOY_PATH in scripts/deploy.env."
ok "$DEPLOY_PATH is a git checkout"

REMOTE_SHA="$(remote_read "cd '$DEPLOY_PATH' && git rev-parse HEAD" | tr -d '\r')"
if [[ "$REMOTE_SHA" == "$LOCAL_SHA" ]]; then
  ok "server is already on this commit — this will be a rebuild"
else
  BEHIND="$(git rev-list --count "$REMOTE_SHA..$LOCAL_SHA" 2>/dev/null || echo '?')"
  ok "server is at ${REMOTE_SHA:0:7}, behind by $BEHIND commit(s)"
fi

remote_read "cd '$DEPLOY_PATH' && test -z \"\$(git status --porcelain)\"" \
  || die "the server checkout has local modifications.
    Inspect them before deploying — this script will not discard anyone's work."
ok "server checkout is clean"

if ! $WITH_ADMIN; then
  RUNNING_ADMIN="$(remote_read "cd '$DEPLOY_PATH' && docker compose --profile admin ps --services --status running" 2>/dev/null | tr -d '\r' || true)"
  if echo "$RUNNING_ADMIN" | grep -Eq '^(admin-api|admin-web|cloudflared)$'; then
    warn "operator console is running on the server but will not be rebuilt; pass --admin to include it"
  fi
fi

PENDING="$(git diff --name-only "$REMOTE_SHA" "$LOCAL_SHA" -- backend/scripts backend/src/db/schema.sql 2>/dev/null | grep -c . || true)"
if [[ "${PENDING:-0}" -gt 0 ]]; then
  warn "$PENDING schema/migration file(s) change in this deploy:"
  git diff --name-only "$REMOTE_SHA" "$LOCAL_SHA" -- backend/scripts backend/src/db/schema.sql \
    | sed 's/^/        /'
  warn "db-init applies these on container start. The backup below is the way back."
fi

# ─── Confirm ──────────────────────────────────────────────────────────────────

if $RESET_DB && ! $DRY_RUN; then
  # Deliberately not a y/N. --yes does not bypass this: the whole point is that
  # a human reads it, and muscle memory must not be able to answer.
  printf '\n%s%sDESTRUCTIVE%s\n' "$BOLD" "$RED" "$OFF"
  printf '    Every family, member, activity, reward and coin balance on\n'
  printf '    %s will be deleted. This cannot be undone.\n' "$DEPLOY_HOST"
  printf '    The backup taken below is the only way back.\n\n'
  printf '    Firebase accounts are NOT deleted — people can still sign in,\n'
  printf '    and will land on the create-a-family wizard as new users.\n'
  $RESET_UPLOADS \
    && printf '    Uploaded avatars will also be deleted.\n' \
    || printf '    Uploaded avatars are kept (orphaned); add --reset-uploads to clear them.\n'
  printf '\n%sType the host name (%s) to confirm:%s ' "$BOLD" "$DEPLOY_HOST" "$OFF"
  read -r reply
  [[ "$reply" == "$DEPLOY_HOST" ]] || die "aborted — you typed '$reply'"
elif ! $DRY_RUN && ! $ASSUME_YES; then
  printf '\n%sDeploy %s to %s?%s [y/N] ' "$BOLD" "${LOCAL_SHA:0:7}" "$DEPLOY_HOST" "$OFF"
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]] || die "aborted"
fi

# ─── Backup ───────────────────────────────────────────────────────────────────

STAMP="$(date +%Y%m%d-%H%M%S)"

if $SKIP_BACKUP; then
  warn "skipping backup at your request"
else
  if $RESET_DB; then
    step "Backup (the only copy of what you are about to destroy)"
  else
    step "Backup (before anything changes)"
  fi
  remote "mkdir -p '$DEPLOY_BACKUP_DIR'"
  # The database. db-init migrates on start, so this must happen first.
  # Plain compose, not $COMPOSE: postgres is not in the admin profile, and on a
  # first --admin deploy the console's env files are not on the server yet, so
  # --profile admin would make compose refuse to run.
  remote "cd '$DEPLOY_PATH' && docker compose exec -T postgres \
            pg_dump -U '$DEPLOY_PG_USER' '$DEPLOY_PG_DB' \
            > '$DEPLOY_BACKUP_DIR/db-$STAMP.sql'"
  # Avatars live on the filesystem via a bind mount, not in the database. A
  # database-only restore would leave every uploaded image broken.
  remote "cd '$DEPLOY_PATH' && tar czf '$DEPLOY_BACKUP_DIR/uploads-$STAMP.tgz' \
            -C backend uploads 2>/dev/null || true"
  $DRY_RUN || ok "db-$STAMP.sql and uploads-$STAMP.tgz in $DEPLOY_BACKUP_DIR"
fi

# ─── Secrets ──────────────────────────────────────────────────────────────────

if $SKIP_SECRETS; then
  warn "skipping secret sync at your request"
else
  step "Secrets"
  for f in "${SECRETS[@]}"; do
    if $DRY_RUN; then
      printf '    %s[dry-run] scp %s -> %s:%s/%s (mode 600)%s\n' \
        "$DIM" "$f" "$DEPLOY_HOST" "$DEPLOY_PATH" "$f" "$OFF"
    else
      remote_read "mkdir -p '$DEPLOY_PATH/$(dirname "$f")'"
      # Land in a temp file, then move into place with tight permissions, so a
      # half-copied secret is never readable as the real thing.
      scp $DEPLOY_SSH_OPTS -q "$REPO_ROOT/$f" "$DEPLOY_HOST:$DEPLOY_PATH/$f.incoming"
      remote_read "install -m 600 '$DEPLOY_PATH/$f.incoming' '$DEPLOY_PATH/$f' \
                   && rm -f '$DEPLOY_PATH/$f.incoming'"
      ok "$f"
    fi
  done
fi

# ─── Deploy ───────────────────────────────────────────────────────────────────

step "Update and rebuild"

# --ff-only: if the server has diverged, stop rather than invent a merge.
remote "cd '$DEPLOY_PATH' && git fetch origin '$BRANCH' && git checkout '$BRANCH' && git pull --ff-only origin '$BRANCH'"

if $RESET_DB; then
  step "Wiping the database"
  # `down -v` removes the containers and every named volume the compose file
  # declares. It declares exactly one, pgdata, so this drops the Postgres data
  # directory and nothing else. Bind mounts (backend/uploads, the secrets) are
  # not volumes and are untouched.
  remote "cd '$DEPLOY_PATH' && $COMPOSE down -v"
  $DRY_RUN || ok "pgdata volume removed — the next start builds an empty database"

  if $RESET_UPLOADS; then
    # Avatars are a bind mount, so the wipe above leaves them behind pointing at
    # rows that no longer exist. Clear the contents, keep the directory: compose
    # bind-mounts it and would otherwise recreate it root-owned.
    remote "find '$DEPLOY_PATH/backend/uploads' -mindepth 1 -delete 2>/dev/null || true"
    $DRY_RUN || ok "uploads cleared"
  fi
fi

remote "cd '$DEPLOY_PATH' && $COMPOSE up --build -d"
remote "cd '$DEPLOY_PATH' && $COMPOSE ps"

if ! $DRY_RUN; then
  DEPLOYED="$(remote_read "cd '$DEPLOY_PATH' && git rev-parse HEAD" | tr -d '\r')"
  if [[ "$DEPLOYED" == "$LOCAL_SHA" ]]; then
    ok "server is on ${DEPLOYED:0:7}"
  else
    die "server ended up on ${DEPLOYED:0:7}, expected ${LOCAL_SHA:0:7}"
  fi
fi

# ─── Verify ───────────────────────────────────────────────────────────────────

step "Verify"

if $DRY_RUN; then
  printf '    %s[dry-run] would probe %s%s\n' "$DIM" "$DEPLOY_URL" "$OFF"
  $WITH_ADMIN && printf '    %s[dry-run] would probe %s%s\n' "$DIM" "$DEPLOY_ADMIN_URL" "$OFF"
else
  printf '    waiting for the API'
  for _ in $(seq 1 30); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$DEPLOY_URL/api/me" || true)"
    [[ "$code" == "401" ]] && break
    printf '.'; sleep 3
  done
  printf '\n'

  FAILED=0

  if $RESET_DB; then
    # "It came up" is not the same as "it came up empty and migrated". Check
    # both: a table that only exists after the migrations, and no rows in it.
    FAMILIES="$(remote_read "cd '$DEPLOY_PATH' && docker compose exec -T postgres \
      psql -U '$DEPLOY_PG_USER' -d '$DEPLOY_PG_DB' -tAc \
      'SELECT COUNT(*) FROM families'" 2>/dev/null | tr -d '\r' || echo '?')"
    REQUESTS="$(remote_read "cd '$DEPLOY_PATH' && docker compose exec -T postgres \
      psql -U '$DEPLOY_PG_USER' -d '$DEPLOY_PG_DB' -tAc \
      'SELECT COUNT(*) FROM personal_time_requests'" 2>/dev/null | tr -d '\r' || echo '?')"
    if [[ "$FAMILIES" == "0" ]]; then ok "database is empty (families: 0)"
    else warn "expected 0 families, got '$FAMILIES'"; FAILED=$((FAILED + 1)); fi
    if [[ "$REQUESTS" == "0" ]]; then ok "migrations ran (personal_time_requests exists, empty)"
    else warn "personal_time_requests missing or unexpected: '$REQUESTS'"; FAILED=$((FAILED + 1)); fi
  fi

  # A mounted route answers 401 for a missing token; an unmounted one falls
  # through to the 404 handler. That is what tells us the new code is live.
  for path in /api/me /api/activities /api/personal-time /api/admin/families; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$DEPLOY_URL$path" || echo 000)"
    if [[ "$code" == "401" ]]; then ok "$path -> 401 (mounted)"
    else warn "$path -> $code"; FAILED=$((FAILED + 1)); fi
  done

  # /api/billing/webhook is POST-only, so a GET returns 404 whether or not it is
  # mounted. Only POST distinguishes "not deployed" (404) from "deployed, and it
  # rejected the empty body" (401).
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
          -X POST -H 'Content-Type: application/json' -d '{}' \
          "$DEPLOY_URL/api/billing/webhook" || echo 000)"
  if [[ "$code" == "401" ]]; then ok "/api/billing/webhook -> 401 (mounted)"
  else warn "/api/billing/webhook -> $code (POST; 404 means billing is not deployed)"; FAILED=$((FAILED + 1)); fi

  for path in / /privacy /terms; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$DEPLOY_URL$path" || echo 000)"
    if [[ "$code" == "200" ]]; then ok "$path -> 200"
    else warn "$path -> $code"; FAILED=$((FAILED + 1)); fi
  done

  if $WITH_ADMIN; then
    RUNNING_SERVICES="$(remote_read "cd '$DEPLOY_PATH' && $COMPOSE ps --status running --services" 2>/dev/null | tr -d '\r' || true)"
    for svc in admin-api admin-web cloudflared; do
      if echo "$RUNNING_SERVICES" | grep -Fqx "$svc"; then
        ok "$svc is running"
      else
        warn "$svc is not running"
        FAILED=$((FAILED + 1))
      fi
    done

    for path in / /admin-api/status; do
      resp="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 10 "$DEPLOY_ADMIN_URL$path" || echo "000")"
      read -r code redir <<< "$resp"
      if [[ "$code" == "302" ]]; then
        host="${redir#https://}"
        host="${host%%/*}"
        if [[ "$redir" == https://* && "$host" == *.cloudflareaccess.com ]]; then
          ok "$DEPLOY_ADMIN_URL$path -> 302 (Cloudflare Access: $host)"
        else
          warn "$DEPLOY_ADMIN_URL$path -> 302 to unexpected location: $redir"
          FAILED=$((FAILED + 1))
        fi
      elif [[ "$code" == "403" ]]; then
        ok "$DEPLOY_ADMIN_URL$path -> 403 (Cloudflare Access blocked)"
      elif [[ "$code" == "200" || "$code" == "401" ]]; then
        printf '    %s! %s%s -> %s: operator console is reachable without Cloudflare Access!%s\n' \
          "$RED" "$DEPLOY_ADMIN_URL" "$path" "$code" "$OFF"
        warn "Cloudflare Access is not protecting $DEPLOY_ADMIN_URL$path"
        FAILED=$((FAILED + 1))
      else
        warn "$DEPLOY_ADMIN_URL$path -> $code (expected 302 redirect to Cloudflare Access or 403)"
        FAILED=$((FAILED + 1))
      fi
    done
  fi

  if [[ "$FAILED" -gt 0 ]]; then
    printf '\n%s%d check(s) did not pass.%s Logs:\n' "$YELLOW" "$FAILED" "$OFF"
    printf '    ssh %s "cd %s && %s logs --tail=80 backend"\n' "$DEPLOY_HOST" "$DEPLOY_PATH" "$COMPOSE"
    if $WITH_ADMIN; then
      printf '    ssh %s "cd %s && %s logs --tail=80 admin-api admin-web cloudflared"\n' "$DEPLOY_HOST" "$DEPLOY_PATH" "$COMPOSE"
    fi
  fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

step "Done"
if $DRY_RUN; then
  echo "    Dry run only — nothing changed."
else
  if $RESET_DB; then
    cat <<EOF

    ${BOLD}The database was wiped and rebuilt empty.${OFF}
    Firebase accounts still exist, so signing in works — everyone lands on the
    create-a-family wizard as a new user. The first person to sign in should
    create the family and invite the others.
EOF
  fi
  cat <<EOF
    Deployed ${LOCAL_SHA:0:7} to $DEPLOY_HOST.

    Still worth doing by hand (docs/deployment-and-delivery.md §2):
      sign in on $DEPLOY_URL, load an avatar, enable push.

    To roll back the code:
      ssh $DEPLOY_HOST "cd $DEPLOY_PATH && git checkout $REMOTE_SHA && $COMPOSE up --build -d"
    Schema too, if a migration is the problem:
      ssh $DEPLOY_HOST "cd $DEPLOY_PATH && docker compose exec -T postgres \\
        psql -U $DEPLOY_PG_USER -d $DEPLOY_PG_DB < $DEPLOY_BACKUP_DIR/db-$STAMP.sql"
EOF
fi
