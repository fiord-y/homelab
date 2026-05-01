#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
SERVICES_DIR="$ROOT_DIR/services"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; return 1; }; }

require_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo ".env not found. Run: $0 bootstrap"
    exit 1
  fi
}

compose_files() {
  local files=()
  while IFS= read -r -d '' file; do files+=("-f" "$file"); done < <(find "$SERVICES_DIR" -mindepth 2 -maxdepth 2 -name compose.yml -print0 | sort -z)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No service compose files found under $SERVICES_DIR" >&2
    exit 1
  fi
  echo "${files[@]}"
}

dc() {
  require_env
  # shellcheck disable=SC2086
  docker compose --project-directory "$ROOT_DIR" --env-file "$ENV_FILE" $(compose_files) "$@"
}

validate() {
  local ok=0
  require_cmd docker || ok=1
  docker compose version >/dev/null 2>&1 || { echo "Missing Docker Compose plugin"; ok=1; }
  require_cmd tailscale || ok=1
  require_cmd openssl || ok=1
  [[ -S /var/run/docker.sock ]] || { echo "Docker socket not found at /var/run/docker.sock"; ok=1; }
  tailscale status >/dev/null 2>&1 || { echo "Tailscale is not connected. Run: sudo tailscale up"; ok=1; }

  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC2086
    docker compose --project-directory "$ROOT_DIR" --env-file "$ENV_FILE" $(compose_files) config >/dev/null || ok=1
  else
    echo ".env missing (run bootstrap first)."
    ok=1
  fi

  if [[ "$ok" -ne 0 ]]; then
    echo "Validation failed. Fix errors above."
    exit 1
  fi
  echo "Validation passed."
}

bootstrap() {
  if [[ -f "$ENV_FILE" ]]; then
    read -r -p ".env already exists. Overwrite? [y/N] " ok
    [[ "$ok" =~ ^[Yy]$ ]] || exit 0
  fi

  cp "$ROOT_DIR/.env.example" "$ENV_FILE"
  read -r -p "Base domain (e.g. homelab.ts.net): " domain
  read -r -p "Timezone (e.g. UTC): " tz
  read -r -p "Email for admin/certs: " email
  sed -i "s/example.ts.net/${domain}/g" "$ENV_FILE"
  sed -i "s|TZ=UTC|TZ=${tz}|" "$ENV_FILE"
  sed -i "s/admin@example.com/${email}/g" "$ENV_FILE"
  sed -i "s/AUTHENTIK_SECRET_KEY=change_me/AUTHENTIK_SECRET_KEY=$(openssl rand -hex 32)/" "$ENV_FILE"
  sed -i "s/AUTHENTIK_POSTGRES_PASSWORD=change_me/AUTHENTIK_POSTGRES_PASSWORD=$(openssl rand -hex 24)/" "$ENV_FILE"
  sed -i "s/AUTHENTIK_REDIS_PASSWORD=change_me/AUTHENTIK_REDIS_PASSWORD=$(openssl rand -hex 24)/" "$ENV_FILE"
  sed -i "s/AUTHENTIK_BOOTSTRAP_PASSWORD=change_me/AUTHENTIK_BOOTSTRAP_PASSWORD=$(openssl rand -hex 16)/" "$ENV_FILE"
  sed -i "s/AUTHENTIK_BOOTSTRAP_TOKEN=change_me/AUTHENTIK_BOOTSTRAP_TOKEN=$(openssl rand -hex 24)/" "$ENV_FILE"
  sed -i "s/NEXTCLOUD_DB_PASSWORD=change_me/NEXTCLOUD_DB_PASSWORD=$(openssl rand -hex 24)/" "$ENV_FILE"
  sed -i "s/NEXTCLOUD_ADMIN_PASSWORD=change_me/NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -hex 16)/" "$ENV_FILE"
  if ! grep -q '^DOCKER_API_VERSION=' "$ENV_FILE"; then
    echo 'DOCKER_API_VERSION=1.41' >> "$ENV_FILE"
  fi
  mkdir -p "$ROOT_DIR/data"
  echo "Bootstrap complete: $ENV_FILE"
}

add_service() {
  local name="${1:-}"
  [[ -n "$name" ]] || { echo "Usage: $0 add-service <service_name>"; exit 1; }
  local dir="$SERVICES_DIR/$name"
  mkdir -p "$dir"
  cat > "$dir/compose.yml" <<TEMPLATE
services:
  $name:
    image: your-image:latest
    restart: unless-stopped
    labels:
      - traefik.enable=true
      - traefik.http.routers.${name}.rule=Host(\`${name}.\${DOMAIN}\`)
      - traefik.http.routers.${name}.entrypoints=websecure
      - traefik.http.routers.${name}.tls.certresolver=tailscale
      - traefik.http.routers.${name}.middlewares=\${TRAEFIK_AUTH_MIDDLEWARE}
      - traefik.http.services.${name}.loadbalancer.server.port=8080
TEMPLATE
  echo "Created $dir/compose.yml"
}

case "${1:-}" in
  validate) validate ;;
  bootstrap) bootstrap ;;
  up) dc up -d ;;
  down) dc down ;;
  restart) dc down && dc up -d ;;
  ps) dc ps ;;
  logs) dc logs -f --tail=200 ;;
  pull) dc pull ;;
  reset-hard)
    require_env
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    target_data_dir="${DATA_DIR:-$ROOT_DIR/data}"
    [[ "$target_data_dir" = /* ]] || target_data_dir="$ROOT_DIR/${target_data_dir#./}"
    read -r -p "This deletes all containers and all data under $target_data_dir. Continue? [y/N] " ok
    [[ "$ok" =~ ^[Yy]$ ]] || exit 0
    dc down -v --remove-orphans || true
    if [[ -n "$target_data_dir" && "$target_data_dir" != "/" ]]; then
      rm -rf "$target_data_dir"
    fi
    echo "Hard reset complete."
    ;;
  add-service) shift; add_service "$@" ;;
  *)
    echo "Usage: $0 {validate|bootstrap|up|down|restart|ps|logs|pull|reset-hard|add-service <name>}"
    exit 1
    ;;
esac
