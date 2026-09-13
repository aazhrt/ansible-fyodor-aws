# Ansible Infrastructure Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a production-grade, modular Ansible repository (`/home/admin/ansible-infra`) that standardizes base OS configuration, security hardening, Docker engine, and adopts existing running container stacks (`/srv/docker` and `/opt/infra/monitoring`) with zero downtime and strict secret encryption via Ansible Vault.

**Architecture:** Enterprise multi-environment layout (`inventories/production`), modular roles (`common`, `security`, `docker`, `docker_services`, `monitoring`), hierarchical variables (`group_vars`, `host_vars`), non-destructive compose management, and hybrid execution support (local and remote SSH).

**Tech Stack:** Ansible Core 2.19+, Jinja2, Docker Compose v2, UFW, Fail2ban, Systemd, Debian GNU/Linux 13 (Trixie).

**Spec:** [`docs/superpowers/specs/2026-09-13-ansible-infra-architecture-design.md`](file:///home/admin/ansible-infra/docs/superpowers/specs/2026-09-13-ansible-infra-architecture-design.md)

## Global Constraints

- Platform: Debian GNU/Linux 13 (Trixie), kernel Linux 6.12+
- Existing containers in `/srv/docker` and `/opt/infra/monitoring` must NOT suffer data loss or unnecessary restarts.
- Zero plaintext secrets committed to Git (all sensitive keys prefixed with `vault_` and placed in `vault.yml`).
- Use FQCN (Fully Qualified Collection Names) for Ansible core modules (e.g. `ansible.builtin.apt`, `ansible.builtin.template`).
- Every role must be idempotent: a subsequent playbook run must yield `changed=0 failed=0`.

---

### Task 1: Repository Foundation, Configuration & Inventory Hierarchy

**Files:**
- Create: `/home/admin/ansible-infra/.gitignore`
- Create: `/home/admin/ansible-infra/ansible.cfg`
- Create: `/home/admin/ansible-infra/inventories/production/hosts.yml`
- Create: `/home/admin/ansible-infra/inventories/production/group_vars/all.yml`
- Create: `/home/admin/ansible-infra/inventories/production/group_vars/servers.yml`
- Create: `/home/admin/ansible-infra/inventories/production/host_vars/server-prod/vars.yml`
- Create: `/home/admin/ansible-infra/inventories/production/host_vars/server-prod/vault.example.yml`

**Interfaces:**
- Consumes: Host system environment and users (`admin`, `sysadmin`).
- Produces: Base inventory resolution and Ansible defaults for all playbooks.

- [ ] **Step 1: Create `.gitignore` to prevent secret and retry file leaks**

```gitignore
*.retry
.vault_pass
*.log
.DS_Store
__pycache__/
*.pyc
inventories/production/host_vars/*/vault.yml
!inventories/production/host_vars/*/vault.example.yml
```

- [ ] **Step 2: Create `ansible.cfg`**

```ini
[defaults]
inventory = inventories/production/hosts.yml
roles_path = roles
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
bin_ansible_callbacks = True
pipelining = True
timeout = 30

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
```

- [ ] **Step 3: Create inventory and variable hierarchy**

`inventories/production/hosts.yml`:
```yaml
all:
  children:
    servers:
      hosts:
        server-prod:
          ansible_host: 127.0.0.1
          ansible_connection: local
          ansible_user: admin
```

`inventories/production/group_vars/all.yml`:
```yaml
---
timezone: "Asia/Jakarta"
system_locale: "en_US.UTF-8"
admin_users:
  - admin
  - sysadmin
common_packages:
  - curl
  - git
  - htop
  - jq
  - unzip
  - ca-certificates
  - gnupg
  - software-properties-common
  - rsync
  - tree
```

`inventories/production/group_vars/servers.yml`:
```yaml
---
sysctl_settings:
  vm.max_map_count: 262144
  fs.file-max: 2097152
  net.core.somaxconn: 65535
journald_max_use: "500M"
```

`inventories/production/host_vars/server-prod/vars.yml`:
```yaml
---
mysql_root_password: "{{ vault_mysql_root_password | default('CHANGE_ME_IN_VAULT') }}"
cloudflared_token: "{{ vault_cloudflared_token | default('') }}"
grafana_admin_password: "{{ vault_grafana_admin_password | default('admin') }}"
syncthing_gui_password: "{{ vault_syncthing_gui_password | default('') }}"
```

`inventories/production/host_vars/server-prod/vault.example.yml`:
```yaml
---
# Rename or copy this file to vault.yml and encrypt using:
# ansible-vault encrypt inventories/production/host_vars/server-prod/vault.yml
vault_mysql_root_password: "ReplaceWithActualMySQLRootPassword"
vault_cloudflared_token: "ReplaceWithCloudflareTunnelToken"
vault_grafana_admin_password: "ReplaceWithGrafanaAdminPassword"
vault_syncthing_gui_password: "ReplaceWithSyncthingPassword"
```

- [ ] **Step 4: Verify inventory parsing with `ansible-inventory`**

Run: `cd /home/admin/ansible-infra && ansible-inventory -i inventories/production/hosts.yml --list`
Expected: Valid JSON output with `servers` containing `server-prod` and merged `all` group variables.

- [ ] **Step 5: Commit changes**

```bash
cd /home/admin/ansible-infra
git add .gitignore ansible.cfg inventories/
git commit -m "feat: establish repository foundation and inventory hierarchy"
```

---

### Task 2: Role `common` (System Baseline & Performance Tuning)

**Files:**
- Create: `/home/admin/ansible-infra/roles/common/defaults/main.yml`
- Create: `/home/admin/ansible-infra/roles/common/tasks/main.yml`
- Create: `/home/admin/ansible-infra/roles/common/handlers/main.yml`

**Interfaces:**
- Consumes: `timezone`, `system_locale`, `common_packages`, `sysctl_settings`, `journald_max_use`.
- Produces: Standardized base OS packages, kernel limits, and systemd log caps.

- [ ] **Step 1: Write `roles/common/defaults/main.yml`**

```yaml
---
common_timezone: "{{ timezone | default('Asia/Jakarta') }}"
common_locale: "{{ system_locale | default('en_US.UTF-8') }}"
common_packages_list: "{{ common_packages }}"
common_sysctl: "{{ sysctl_settings }}"
common_journald_limit: "{{ journald_max_use | default('500M') }}"
```

- [ ] **Step 2: Write `roles/common/handlers/main.yml`**

```yaml
---
- name: Reload sysctl
  ansible.builtin.command:
    cmd: sysctl --system
  changed_when: true

- name: Restart systemd-journald
  ansible.builtin.systemd:
    name: systemd-journald
    state: restarted
```

- [ ] **Step 3: Write `roles/common/tasks/main.yml`**

```yaml
---
- name: Set system timezone
  community.general.timezone:
    name: "{{ common_timezone }}"

- name: Ensure locale is generated
  ansible.builtin.locale_gen:
    name: "{{ common_locale }}"
    state: present

- name: Update apt cache and install baseline packages
  ansible.builtin.apt:
    name: "{{ common_packages_list }}"
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: Configure sysctl kernel parameters
  ansible.builtin.sysctl:
    name: "{{ item.key }}"
    value: "{{ item.value }}"
    state: present
    reload: true
    sysctl_set: true
  loop: "{{ common_sysctl | dict2items }}"
  notify: Reload sysctl

- name: Configure journald log retention limit
  ansible.builtin.lineinfile:
    path: /etc/systemd/journald.conf
    regexp: '^#?SystemMaxUse='
    line: "SystemMaxUse={{ common_journald_limit }}"
    state: present
  notify: Restart systemd-journald
```

- [ ] **Step 4: Test syntax with ad-hoc playbook test**

Run: `ansible localhost -m include_role -a name=common -i inventories/production/hosts.yml --syntax-check` or syntax test playbook.
Expected: Syntax check success.

- [ ] **Step 5: Commit changes**

```bash
cd /home/admin/ansible-infra
git add roles/common/
git commit -m "feat(roles): add common baseline and sysctl tuning role"
```

---

### Task 3: Role `security` (SSH Hardening, UFW, Fail2ban)

**Files:**
- Create: `/home/admin/ansible-infra/roles/security/defaults/main.yml`
- Create: `/home/admin/ansible-infra/roles/security/templates/99-hardened.conf.j2`
- Create: `/home/admin/ansible-infra/roles/security/templates/jail.local.j2`
- Create: `/home/admin/ansible-infra/roles/security/tasks/main.yml`
- Create: `/home/admin/ansible-infra/roles/security/handlers/main.yml`

**Interfaces:**
- Consumes: Open firewall ports (`22`, `80`, `443`), Tailscale interface (`tailscale0`).
- Produces: Hardened SSH daemon, active UFW rules, and Fail2ban brute-force protection.

- [ ] **Step 1: Write `roles/security/defaults/main.yml`**

```yaml
---
security_ssh_port: 22
security_ssh_permit_root: "prohibit-password"
security_ssh_max_auth_tries: 5
security_ssh_permit_empty_passwords: "no"

security_ufw_default_incoming: "deny"
security_ufw_default_outgoing: "allow"
security_ufw_allowed_ports:
  - { port: "{{ security_ssh_port }}", proto: "tcp", comment: "SSH" }
  - { port: 80, proto: "tcp", comment: "HTTP" }
  - { port: 443, proto: "tcp", comment: "HTTPS" }
security_ufw_allowed_interfaces:
  - "tailscale0"

security_fail2ban_bantime: "1h"
security_fail2ban_findtime: "10m"
security_fail2ban_maxretry: 5
```

- [ ] **Step 2: Write templates**

`roles/security/templates/99-hardened.conf.j2`:
```text
# Managed by Ansible - do not edit directly
Port {{ security_ssh_port }}
PermitRootLogin {{ security_ssh_permit_root }}
PermitEmptyPasswords {{ security_ssh_permit_empty_passwords }}
MaxAuthTries {{ security_ssh_max_auth_tries }}
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

`roles/security/templates/jail.local.j2`:
```ini
[DEFAULT]
bantime = {{ security_fail2ban_bantime }}
findtime = {{ security_fail2ban_findtime }}
maxretry = {{ security_fail2ban_maxretry }}
backend = systemd

[sshd]
enabled = true
port = {{ security_ssh_port }}
mode = aggressive
```

- [ ] **Step 3: Write `roles/security/handlers/main.yml`**

```yaml
---
- name: Restart ssh
  ansible.builtin.service:
    name: ssh
    state: restarted

- name: Reload ufw
  community.general.ufw:
    state: reloaded

- name: Restart fail2ban
  ansible.builtin.service:
    name: fail2ban
    state: restarted
```

- [ ] **Step 4: Write `roles/security/tasks/main.yml`**

```yaml
---
- name: Install security packages (ufw, fail2ban)
  ansible.builtin.apt:
    name:
      - ufw
      - fail2ban
    state: present

- name: Deploy hardened sshd drop-in configuration
  ansible.builtin.template:
    src: 99-hardened.conf.j2
    dest: /etc/ssh/sshd_config.d/99-hardened.conf
    owner: root
    group: root
    mode: '0644'
  notify: Restart ssh

- name: Deploy fail2ban jail configuration
  ansible.builtin.template:
    src: jail.local.j2
    dest: /etc/fail2ban/jail.local
    owner: root
    group: root
    mode: '0644'
  notify: Restart fail2ban

- name: Configure UFW default incoming policy
  community.general.ufw:
    direction: incoming
    default: "{{ security_ufw_default_incoming }}"

- name: Configure UFW default outgoing policy
  community.general.ufw:
    direction: outgoing
    default: "{{ security_ufw_default_outgoing }}"

- name: Allow specified ports through UFW
  community.general.ufw:
    rule: allow
    port: "{{ item.port | string }}"
    proto: "{{ item.proto }}"
    comment: "{{ item.comment }}"
  loop: "{{ security_ufw_allowed_ports }}"

- name: Allow traffic on trusted interfaces
  community.general.ufw:
    rule: allow
    interface: "{{ item }}"
    direction: in
  loop: "{{ security_ufw_allowed_interfaces }}"

- name: Enable UFW firewall
  community.general.ufw:
    state: enabled
```

- [ ] **Step 5: Verify task definitions and commit**

```bash
cd /home/admin/ansible-infra
git add roles/security/
git commit -m "feat(roles): add security role for SSH hardening, UFW, and fail2ban"
```

---

### Task 4: Role `docker` (Docker Engine & Compose Runtime)

**Files:**
- Create: `/home/admin/ansible-infra/roles/docker/defaults/main.yml`
- Create: `/home/admin/ansible-infra/roles/docker/templates/daemon.json.j2`
- Create: `/home/admin/ansible-infra/roles/docker/tasks/main.yml`
- Create: `/home/admin/ansible-infra/roles/docker/handlers/main.yml`

**Interfaces:**
- Consumes: Admin users list (`admin`, `sysadmin`).
- Produces: Docker CE service with JSON log rotation and live-restore enabled.

- [ ] **Step 1: Write `roles/docker/defaults/main.yml`**

```yaml
---
docker_apt_arch: "amd64"
docker_apt_repository: "deb [arch={{ docker_apt_arch }} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian {{ ansible_distribution_release }} stable"
docker_packages:
  - docker-ce
  - docker-ce-cli
  - containerd.io
  - docker-buildx-plugin
  - docker-compose-plugin
docker_users: "{{ admin_users }}"
docker_log_max_size: "50m"
docker_log_max_file: "3"
docker_live_restore: true
```

- [ ] **Step 2: Write `roles/docker/templates/daemon.json.j2`**

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "{{ docker_log_max_size }}",
    "max-file": "{{ docker_log_max_file }}"
  },
  "live-restore": {{ docker_live_restore | to_json }}
}
```

- [ ] **Step 3: Write `roles/docker/handlers/main.yml`**

```yaml
---
- name: Restart docker
  ansible.builtin.service:
    name: docker
    state: restarted
```

- [ ] **Step 4: Write `roles/docker/tasks/main.yml`**

```yaml
---
- name: Ensure /etc/apt/keyrings exists
  ansible.builtin.file:
    path: /etc/apt/keyrings
    state: directory
    mode: '0755'

- name: Download Docker official GPG key
  ansible.builtin.get_url:
    url: https://download.docker.com/linux/debian/gpg
    dest: /etc/apt/keyrings/docker.asc
    mode: '0644'
    force: false

- name: Add Docker official apt repository
  ansible.builtin.apt_repository:
    repo: "{{ docker_apt_repository }}"
    filename: docker
    state: present

- name: Install Docker CE and Compose plugin
  ansible.builtin.apt:
    name: "{{ docker_packages }}"
    state: present
    update_cache: true

- name: Configure Docker daemon settings (/etc/docker/daemon.json)
  ansible.builtin.template:
    src: daemon.json.j2
    dest: /etc/docker/daemon.json
    owner: root
    group: root
    mode: '0644'
  notify: Restart docker

- name: Ensure administrative users are in docker group
  ansible.builtin.user:
    name: "{{ item }}"
    groups: docker
    append: true
  loop: "{{ docker_users }}"

- name: Ensure Docker service is running and enabled
  ansible.builtin.service:
    name: docker
    state: started
    enabled: true
```

- [ ] **Step 5: Commit changes**

```bash
cd /home/admin/ansible-infra
git add roles/docker/
git commit -m "feat(roles): add docker engine and compose configuration role"
```

---

### Task 5: Role `docker_services` (Adopting `/srv/docker` Stacks)

**Files:**
- Create: `/home/admin/ansible-infra/roles/docker_services/defaults/main.yml`
- Create: `/home/admin/ansible-infra/roles/docker_services/tasks/main.yml`
- Create: `/home/admin/ansible-infra/roles/docker_services/handlers/main.yml`

**Interfaces:**
- Consumes: Target stacks in `/srv/docker` (`nginx`, `mysql`, `cloudflared`, `phpmyadmin`, `portainer`, `syncthing`).
- Produces: Safe, non-destructive orchestration of existing Docker Compose services.

- [ ] **Step 1: Write `roles/docker_services/defaults/main.yml`**

```yaml
---
docker_services_base_dir: "/srv/docker"
docker_services_stacks:
  - name: "nginx"
    dir: "{{ docker_services_base_dir }}/nginx"
  - name: "mysql"
    dir: "{{ docker_services_base_dir }}/mysql"
  - name: "cloudflared"
    dir: "{{ docker_services_base_dir }}/cloudflared"
  - name: "phpmyadmin"
    dir: "{{ docker_services_base_dir }}/phpmyadmin"
  - name: "portainer"
    dir: "{{ docker_services_base_dir }}/portainer"
  - name: "syncthing"
    dir: "{{ docker_services_base_dir }}/syncthing"
```

- [ ] **Step 2: Write `roles/docker_services/handlers/main.yml`**

```yaml
---
- name: Reload global-nginx
  ansible.builtin.command:
    cmd: docker exec global-nginx nginx -s reload
  failed_when: false
  changed_when: true
```

- [ ] **Step 3: Write `roles/docker_services/tasks/main.yml`**

```yaml
---
- name: Verify existing compose directories exist in /srv/docker
  ansible.builtin.stat:
    path: "{{ item.dir }}"
  loop: "{{ docker_services_stacks }}"
  register: stack_stats

- name: Ensure stack compose files are running (non-destructive)
  ansible.builtin.command:
    cmd: docker compose up -d --remove-orphans
    chdir: "{{ item.item.dir }}"
  loop: "{{ stack_stats.results }}"
  when: item.stat.exists
  register: compose_run
  changed_when: "'Started' in compose_run.stdout or 'Created' in compose_run.stdout or 'Recreated' in compose_run.stdout"

- name: Verify health of core containers
  ansible.builtin.command:
    cmd: docker ps --format "{{ '{{' }}.Names{{ '}}' }}: {{ '{{' }}.Status{{ '}}' }}"
  register: active_containers
  changed_when: false

- name: Display status of core services
  ansible.builtin.debug:
    var: active_containers.stdout_lines
```

- [ ] **Step 4: Commit changes**

```bash
cd /home/admin/ansible-infra
git add roles/docker_services/
git commit -m "feat(roles): add docker_services role for non-destructive stack management"
```

---

### Task 6: Role `monitoring` (Observability in `/opt/infra/monitoring`)

**Files:**
- Create: `/home/admin/ansible-infra/roles/monitoring/defaults/main.yml`
- Create: `/home/admin/ansible-infra/roles/monitoring/tasks/main.yml`
- Create: `/home/admin/ansible-infra/roles/monitoring/handlers/main.yml`

**Interfaces:**
- Consumes: Monitoring directory `/opt/infra/monitoring` (grafana, loki, promtail, node-exporter).
- Produces: Ensured uptime and idempotent management of the observability stack.

- [ ] **Step 1: Write `roles/monitoring/defaults/main.yml`**

```yaml
---
monitoring_dir: "/opt/infra/monitoring"
monitoring_grafana_port: 3006
monitoring_loki_port: 3100
```

- [ ] **Step 2: Write `roles/monitoring/handlers/main.yml`**

```yaml
---
- name: Restart monitoring stack
  ansible.builtin.command:
    cmd: docker compose restart
    chdir: "{{ monitoring_dir }}"
  changed_when: true
```

- [ ] **Step 3: Write `roles/monitoring/tasks/main.yml`**

```yaml
---
- name: Check if monitoring directory exists
  ansible.builtin.stat:
    path: "{{ monitoring_dir }}"
  register: mon_dir_stat

- name: Ensure monitoring compose stack is running
  ansible.builtin.command:
    cmd: docker compose up -d
    chdir: "{{ monitoring_dir }}"
  when: mon_dir_stat.stat.exists
  register: mon_compose_run
  changed_when: "'Started' in mon_compose_run.stdout or 'Created' in mon_compose_run.stdout or 'Recreated' in mon_compose_run.stdout"

- name: Verify monitoring endpoints are reachable
  ansible.builtin.uri:
    url: "http://127.0.0.1:{{ monitoring_grafana_port }}/api/health"
    status_code: 200
  register: grafana_health
  retries: 3
  delay: 5
  until: grafana_health.status == 200
  ignore_errors: true
```

- [ ] **Step 4: Commit changes**

```bash
cd /home/admin/ansible-infra
git add roles/monitoring/
git commit -m "feat(roles): add monitoring stack role"
```

---

### Task 7: Master Playbooks, Sub-playbooks, Helper Scripts & Vault Tools

**Files:**
- Create: `/home/admin/ansible-infra/playbooks/site.yml`
- Create: `/home/admin/ansible-infra/playbooks/bootstrap.yml`
- Create: `/home/admin/ansible-infra/playbooks/security.yml`
- Create: `/home/admin/ansible-infra/playbooks/services.yml`
- Create: `/home/admin/ansible-infra/scripts/run-local.sh`
- Create: `/home/admin/ansible-infra/scripts/run-remote.sh`
- Create: `/home/admin/ansible-infra/scripts/vault-manage.sh`

**Interfaces:**
- Consumes: All roles (`common`, `security`, `docker`, `docker_services`, `monitoring`).
- Produces: Complete master execution entrypoints and administrative CLI scripts.

- [ ] **Step 1: Write `playbooks/site.yml`**

```yaml
---
- name: "Infrastructure Master Orchestration: Base System & Security"
  hosts: all
  become: true
  gather_facts: true
  roles:
    - role: common
      tags: [common, base]
    - role: security
      tags: [security]

- name: "Infrastructure Master Orchestration: Docker Runtime & Stacks"
  hosts: all
  become: true
  gather_facts: false
  roles:
    - role: docker
      tags: [docker]
    - role: docker_services
      tags: [docker_services, services]
    - role: monitoring
      tags: [monitoring]
```

- [ ] **Step 2: Write sub-playbooks**

`playbooks/bootstrap.yml`:
```yaml
---
- name: "Bootstrap Node Prerequisites"
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Ensure python3 and sudo are installed
      ansible.builtin.raw: apt-get update && apt-get install -y python3 sudo python3-apt
      changed_when: false
```

`playbooks/security.yml`:
```yaml
---
- name: "Targeted Security & Firewall Update"
  hosts: all
  become: true
  roles:
    - role: security
      tags: [security]
```

`playbooks/services.yml`:
```yaml
---
- name: "Targeted Container Stacks & Monitoring Run"
  hosts: all
  become: true
  roles:
    - role: docker_services
      tags: [docker_services, services]
    - role: monitoring
      tags: [monitoring]
```

- [ ] **Step 3: Write helper scripts**

`scripts/run-local.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "==> Executing Ansible locally on this server..."
ansible-playbook playbooks/site.yml -i inventories/production/hosts.yml "$@"
```

`scripts/run-remote.sh`:
```bash
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
```

`scripts/vault-manage.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_FILE="$SCRIPT_DIR/inventories/production/host_vars/server-prod/vault.yml"
EXAMPLE_FILE="$SCRIPT_DIR/inventories/production/host_vars/server-prod/vault.example.yml"

case "${1:-}" in
  init)
    if [ -f "$VAULT_FILE" ]; then
      echo "vault.yml already exists."
    else
      cp "$EXAMPLE_FILE" "$VAULT_FILE"
      echo "Created vault.yml from vault.example.yml. Now encrypting..."
      ansible-vault encrypt "$VAULT_FILE"
    fi
    ;;
  edit)
    ansible-vault edit "$VAULT_FILE"
    ;;
  view)
    ansible-vault view "$VAULT_FILE"
    ;;
  *)
    echo "Usage: $0 {init|edit|view}"
    exit 1
    ;;
esac
```

- [ ] **Step 4: Make scripts executable and test syntax**

Run: `chmod +x scripts/*.sh && ansible-playbook --syntax-check playbooks/site.yml`
Expected: Syntax check passes with 0 errors.

- [ ] **Step 5: Commit changes**

```bash
cd /home/admin/ansible-infra
git add playbooks/ scripts/
git commit -m "feat: add master and sub-playbooks, helper scripts, and vault tools"
```

---

### Task 8: Architecture Mapping & Auditing Documentation (`docs/ARCHITECTURE.md`)

**Files:**
- Create: `/home/admin/ansible-infra/docs/ARCHITECTURE.md`

**Interfaces:**
- Consumes: Completed directory structure and roles.
- Produces: Architectural reference supporting `/zoom-out` mapping and `/improve-codebase-architecture` workflows.

- [ ] **Step 1: Write `docs/ARCHITECTURE.md`**

Documenting:
1. High-level architecture and subsystem diagram (Mermaid).
2. Inventory & Variable Resolution Order (precedence table).
3. Role dependency map and operational tags.
4. Security and secrets boundary.
5. AI Agent commands:
   - How to perform `/zoom-out` (exploring roles and dependencies).
   - How to perform `/improve-codebase-architecture` (identifying duplication, refactoring into roles, vault auditing).

- [ ] **Step 2: Commit documentation**

```bash
cd /home/admin/ansible-infra
git add docs/ARCHITECTURE.md
git commit -m "docs: add comprehensive architecture mapping and audit reference"
```

---

### Task 9: End-to-End Verification & Idempotence Validation

**Files:**
- Verify: Full playbook execution and container continuity.

**Interfaces:**
- Consumes: All playbooks and running server environment.
- Produces: Confirmed working infrastructure and idempotence proof.

- [ ] **Step 1: Perform Syntax & Linter Validation**

Run:
```bash
ansible-playbook --syntax-check playbooks/site.yml
ansible-playbook --syntax-check playbooks/bootstrap.yml
ansible-playbook --syntax-check playbooks/security.yml
ansible-playbook --syntax-check playbooks/services.yml
```
Expected: All 4 playbooks pass syntax verification.

- [ ] **Step 2: Execute Dry-Run Mode (`--check --diff`)**

Run:
```bash
ansible-playbook playbooks/site.yml --check --diff
```
Expected: Playbook previews actions cleanly without fatal errors.

- [ ] **Step 3: Execute Playbook Live**

Run:
```bash
ansible-playbook playbooks/site.yml
```
Expected: Execution completes with `failed=0`.

- [ ] **Step 4: Verify Idempotence (Second Run)**

Run:
```bash
ansible-playbook playbooks/site.yml
```
Expected: `changed=0 failed=0` (or only non-stateful status commands report ok).

- [ ] **Step 5: Verify Container & System Health**

Run:
```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
sudo ufw status verbose
```
Expected: All core containers (`mysql`, `nginx`, `grafana`, `cloudflared`) remain healthy and active.
