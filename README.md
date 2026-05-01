# Homelab (Tailscale + Traefik + Authentik)

Production-oriented, modular homelab layout for a single Fedora host using Docker Compose.

## Architecture
- **Host-only**: Tailscale daemon runs on the host.
- **Containers**: Traefik, Authentik, Nextcloud, Jellyfin, Jellyseerr, Homepage, Dozzle.
- **HTTPS**: Traefik with Tailscale certificate resolver.
- **SSO/Access control**: Authentik forward-auth middleware in Traefik.
- **Modular services**: each service has its own `services/<name>/compose.yml`.

## Quick start
1. Copy/bootstrap config:
   ```bash
   ./scripts/homelab.sh validate
   ./scripts/homelab.sh bootstrap
   ```
2. Ensure host Tailscale is online:
   ```bash
   sudo tailscale up
   ```
3. Start stack:
   ```bash
   ./scripts/homelab.sh up
   ```
4. Check status:
   ```bash
   ./scripts/homelab.sh ps
   ```

## Commands
```bash
./scripts/homelab.sh validate
./scripts/homelab.sh bootstrap
./scripts/homelab.sh up
./scripts/homelab.sh down
./scripts/homelab.sh restart
./scripts/homelab.sh logs
./scripts/homelab.sh pull
./scripts/homelab.sh reset-hard
./scripts/homelab.sh add-service myservice
```

## Add a new service
- Run:
  ```bash
  ./scripts/homelab.sh add-service myservice
  ```
- Edit `services/myservice/compose.yml` and set image/env/port.
- Deploy with:
  ```bash
  ./scripts/homelab.sh up
  ```

## Important notes
- Default `.env` uses placeholders and generated secrets at bootstrap.
- Hard reset removes **all containers/volumes in this project** and deletes the directory pointed by `DATA_DIR` in `.env`.
- Create Authentik applications/providers and map policies/groups to users you share Tailnet with.


## Path notes
- Paths are relative to the repository root by default (`DATA_DIR=./data`) so they work on any host without editing hardcoded absolute paths.
- The manager uses Compose `--project-directory` pinned to repo root, so relative paths like `./data` and `./config` are always resolved from this repository root.
