#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "==> Executing Ansible locally on this server..."
ansible-playbook playbooks/site.yml -i inventories/production/hosts.yml "$@"
