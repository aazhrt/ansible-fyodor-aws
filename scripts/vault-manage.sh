#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_FILE="$SCRIPT_DIR/inventories/production/host_vars/server-prod/vault.yml"
EXAMPLE_FILE="$SCRIPT_DIR/inventories/production/host_vars/server-prod/vault.yml.example"

case "${1:-}" in
  init)
    if [ -f "$VAULT_FILE" ]; then
      echo "vault.yml already exists."
    else
      cp "$EXAMPLE_FILE" "$VAULT_FILE"
      echo "Created vault.yml from vault.yml.example. Now encrypting..."
      ansible-vault encrypt "$VAULT_FILE"
    fi
    ;;
  edit)
    ansible-vault edit "$VAULT_FILE"
    ;;
  view)
    ansible-vault view "$VAULT_FILE"
    ;;
  decrypt)
    ansible-vault decrypt "$VAULT_FILE"
    ;;
  *)
    echo "Usage: $0 {init|edit|view|decrypt}"
    exit 1
    ;;
esac
