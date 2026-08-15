from pathlib import Path

p = Path('.github/workflows/deploy-wesi-ai.yml')
text = p.read_text(encoding='utf-8')

# Validate the connector migration as part of the source bundle gate.
anchor = "          [ \"$count\" -gt 8 ] || { echo \"::error::Incomplete Main Wesi AI hook bundle ($count files)\"; exit 1; }\n"
insert = anchor + "          node --check server/pb_migrations/1786830000_wesi_ai_connector_vault.js\n"
if 'node --check server/pb_migrations/1786830000_wesi_ai_connector_vault.js' not in text:
    if anchor not in text:
        raise RuntimeError('source validation anchor missing')
    text = text.replace(anchor, insert, 1)

# Build an optional sealed connector env bundle. Existing AI deploys keep working
# without these secrets; GitHub Connector remains fail-closed/unavailable.
anchor = "      - name: Deploy Main Wesi AI hooks personas and shared config\n"
block = r'''      - name: Build optional Main connector environment
        env:
          CONNECTOR_VAULT_KEY: ${{ secrets.WESI_CONNECTOR_VAULT_KEY }}
          GITHUB_OAUTH_CLIENT_ID: ${{ secrets.WESI_GITHUB_OAUTH_CLIENT_ID }}
        run: |
          set -euo pipefail
          : > wesi-connectors-env.b64
          if [ -n "${GITHUB_OAUTH_CLIENT_ID:-}" ] && [ -z "${CONNECTOR_VAULT_KEY:-}" ]; then
            echo '::error::WESI_GITHUB_OAUTH_CLIENT_ID requires WESI_CONNECTOR_VAULT_KEY'
            exit 1
          fi
          if [ -n "${CONNECTOR_VAULT_KEY:-}" ]; then
            [[ "$CONNECTOR_VAULT_KEY" =~ ^[A-Za-z0-9_-]{32}$ ]] || { echo '::error::WESI_CONNECTOR_VAULT_KEY must be exactly 32 URL-safe random characters'; exit 1; }
            echo "::add-mask::$CONNECTOR_VAULT_KEY"
            printf 'WESI_CONNECTOR_VAULT_KEY=%s\n' "$(printf '%s' "$CONNECTOR_VAULT_KEY" | base64 -w0)" >> wesi-connectors-env.b64
          fi
          if [ -n "${GITHUB_OAUTH_CLIENT_ID:-}" ]; then
            [[ "$GITHUB_OAUTH_CLIENT_ID" =~ ^[A-Za-z0-9_-]{8,200}$ ]] || { echo '::error::WESI_GITHUB_OAUTH_CLIENT_ID is invalid'; exit 1; }
            printf 'WESI_GITHUB_OAUTH_CLIENT_ID=%s\n' "$(printf '%s' "$GITHUB_OAUTH_CLIENT_ID" | base64 -w0)" >> wesi-connectors-env.b64
          fi
          chmod 600 wesi-connectors-env.b64

''' + anchor
if 'Build optional Main connector environment' not in text:
    if anchor not in text:
        raise RuntimeError('main deploy anchor missing')
    text = text.replace(anchor, block, 1)

# Upload migration + optional connector config with the Main hooks bundle.
old = "          scp \"${SSH[@]}\" server/pb_hooks/wesi_ai_*.js server/pb_hooks/wesi_ai_*.pb.js server/pb_hooks/.wesi-ai-personas.json wesi-ai-relay.json \"$MAIN_USER@$MAIN_HOST:$MAIN_REMOTE/\"\n"
new = "          scp \"${SSH[@]}\" server/pb_hooks/wesi_ai_*.js server/pb_hooks/wesi_ai_*.pb.js server/pb_hooks/.wesi-ai-personas.json server/pb_migrations/1786830000_wesi_ai_connector_vault.js wesi-ai-relay.json wesi-connectors-env.b64 \"$MAIN_USER@$MAIN_HOST:$MAIN_REMOTE/\"\n"
if 'server/pb_migrations/1786830000_wesi_ai_connector_vault.js wesi-ai-relay.json wesi-connectors-env.b64' not in text:
    if old not in text:
        raise RuntimeError('scp anchor missing')
    text = text.replace(old, new, 1)

# Install migration and, only when secrets are supplied, a locked-down systemd
# EnvironmentFile. Avoid removing an existing connector config on ordinary deploy.
anchor = '          HOOK_DIR=/opt/pocketbase/pb_hooks\n'
install = r'''          HOOK_DIR=/opt/pocketbase/pb_hooks
          PB_ROOT=$(dirname "$HOOK_DIR")
          MIGRATION_DIR="$PB_ROOT/pb_migrations"
'''
if 'MIGRATION_DIR="$PB_ROOT/pb_migrations"' not in text:
    if anchor not in text:
        raise RuntimeError('hook dir anchor missing')
    text = text.replace(anchor, install, 1)

anchor = '          install_one "$REMOTE/wesi-ai-relay.json" 0600 "$HOOK_DIR/.wesi-ai-relay.json"\n'
install = anchor + r'''          "${SUDO[@]}" mkdir -p "$MIGRATION_DIR"
          install_one "$REMOTE/1786830000_wesi_ai_connector_vault.js" 0644 "$MIGRATION_DIR/1786830000_wesi_ai_connector_vault.js"
          if [ -s "$REMOTE/wesi-connectors-env.b64" ]; then
            tmp_env="$REMOTE/wesi-ai-connectors.env"
            umask 077
            : > "$tmp_env"
            while IFS= read -r line; do
              [ -n "$line" ] || continue
              key="${line%%=*}"; encoded="${line#*=}"
              case "$key" in WESI_CONNECTOR_VAULT_KEY|WESI_GITHUB_OAUTH_CLIENT_ID) ;; *) echo 'invalid connector env key' >&2; exit 2;; esac
              value="$(printf '%s' "$encoded" | base64 -d)"
              case "$key" in
                WESI_CONNECTOR_VAULT_KEY) [[ "$value" =~ ^[A-Za-z0-9_-]{32}$ ]] || { echo 'invalid vault key' >&2; exit 2; } ;;
                WESI_GITHUB_OAUTH_CLIENT_ID) [[ "$value" =~ ^[A-Za-z0-9_-]{8,200}$ ]] || { echo 'invalid GitHub OAuth client id' >&2; exit 2; } ;;
              esac
              printf '%s=%s\n' "$key" "$value" >> "$tmp_env"
            done < "$REMOTE/wesi-connectors-env.b64"
            "${SUDO[@]}" install -o root -g "$PB_GROUP" -m 0640 "$tmp_env" /etc/wesi-ai-connectors.env
            "${SUDO[@]}" mkdir -p /etc/systemd/system/pocketbase.service.d
            printf '%s\n' '[Service]' 'EnvironmentFile=-/etc/wesi-ai-connectors.env' | "${SUDO[@]}" tee /etc/systemd/system/pocketbase.service.d/wesi-ai-connectors.conf >/dev/null
            "${SUDO[@]}" chmod 0644 /etc/systemd/system/pocketbase.service.d/wesi-ai-connectors.conf
            "${SUDO[@]}" systemctl daemon-reload
          fi
'''
if 'wesi-ai-connectors.env' not in text:
    if anchor not in text:
        raise RuntimeError('relay config install anchor missing')
    text = text.replace(anchor, install, 1)

# Clean local sealed connector bundle and verify protected route after restart.
text = text.replace('          rm -f wesi-ai-relay.json\n', '          rm -f wesi-ai-relay.json wesi-connectors-env.b64\n', 1)
anchor = '          check_route GET /api/wesi/ai/capabilities\n'
if 'check_route GET /api/wesi/ai/connectors' not in text:
    if anchor not in text:
        raise RuntimeError('verification anchor missing')
    text = text.replace(anchor, anchor + '          check_route GET /api/wesi/ai/connectors\n', 1)

p.write_text(text, encoding='utf-8')
print('connector production deploy hardening applied')
