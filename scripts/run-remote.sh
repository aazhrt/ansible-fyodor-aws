#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <target-host-or-ip> [ansible-playbook options...]"
  exit 1
fi

TARGET="$1"
shift

echo "==> Executing Ansible remotely against $TARGET via SSH..."
ansible-playbook playbooks/site.yml -i inventories/production/hosts.yml \
  -e "ansible_host=$TARGET" -e "ansible_connection=ssh" "$@"
