# Architecture Design Specification: Ansible Infrastructure Automation

- **Date:** 2026-09-13
- **Status:** Approved
- **Scope:** Server Base OS, Security Hardening, Docker Runtime, Core Docker Stacks (`/srv/docker`), Monitoring Stack (`/opt/infra/monitoring`)
- **Target Host:** Debian GNU/Linux 13 (Trixie) - Localhost & Remote SSH execution
- **Repository Location:** `/home/admin/ansible-infra`

---

## 1. Executive Summary & Objectives

This specification defines the architectural design, directory hierarchy, modular role decomposition, secrets management strategy, and operational workflows for automating and standardizing the server infrastructure using **Ansible (Core 2.19+)**.

The server currently runs several active workloads:
- **Core Docker services** in `/srv/docker` (Nginx reverse proxy, MySQL 8.4, Cloudflared tunnel, phpMyAdmin, Portainer, Syncthing).
- **Observability stack** in `/opt/infra/monitoring` (Prometheus Node-Exporter, Grafana, Loki, Promtail).
- **System services** (SSH, Tailscale network mesh).

### Primary Goals
1. **Best-Practice Modularity**: Decouple infrastructure components into isolated, reusable Ansible roles (`common`, `security`, `docker`, `docker_services`, `monitoring`).
2. **Zero-Downtime & Non-Destructive Adoption**: Ensure existing persistent volumes and running containers are adopted without downtime, data loss, or unnecessary restarts.
3. **Enterprise Secrets Security**: Encrypt all sensitive tokens and passwords using AES-256 via Ansible Vault, with a committed plaintext `vault.yml.example` reference.
4. **Dual Execution Model (Hybrid)**: Support both direct local execution on the host (`--connection=local`) and remote control via SSH from administrative workstations or CI/CD pipelines.
5. **Architectural Transparency**: Structure the codebase so that tools and AI agents can map, audit, and refactor roles effortlessly (addressing `/zoom-out` mapping and architecture analysis).

---

## 2. Directory Layout & Repository Architecture

The repository will be structured under `/home/admin/ansible-infra` following official Ansible best practices:

```text
/home/admin/ansible-infra/
├── .gitignore
├── ansible.cfg
├── docs/
│   ├── ARCHITECTURE.md
│   └── superpowers/
│       └── specs/
│           └── 2026-09-13-ansible-infra-architecture-design.md
├── inventories/
│   ├── production/
│   │   ├── hosts.yml
│   │   ├── group_vars/
│   │   │   ├── all.yml
│   │   │   └── servers.yml
│   │   └── host_vars/
│   │       └── server-prod/
│   │           ├── vars.yml
│   │           ├── vault.yml
│   │           └── vault.yml.example
│   └── staging/
│       └── hosts.yml
├── playbooks/
│   ├── site.yml
│   ├── bootstrap.yml
│   ├── security.yml
│   └── services.yml
├── roles/
│   ├── common/
│   │   ├── defaults/main.yml
│   │   ├── tasks/main.yml
│   │   └── handlers/main.yml
│   ├── security/
│   │   ├── defaults/main.yml
│   │   ├── tasks/main.yml
│   │   └── handlers/main.yml
│   ├── docker/
│   │   ├── defaults/main.yml
│   │   ├── tasks/main.yml
│   │   └── handlers/main.yml
│   ├── docker_services/
│   │   ├── defaults/main.yml
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   └── templates/
│   └── monitoring/
│       ├── defaults/main.yml
│       ├── tasks/main.yml
│       ├── handlers/main.yml
│       └── templates/
└── scripts/
    ├── run-local.sh
    ├── run-remote.sh
    └── vault-manage.sh
```

---

## 3. Configuration & Inventory Specifications

### 3.1 `ansible.cfg`
Defines operational defaults to optimize performance and usability:
- `inventory = inventories/production/hosts.yml`
- `roles_path = roles`
- `host_key_checking = False`
- `pipelining = True` (speeds up execution over SSH)
- `vault_password_file = .vault_pass` (conditional fallback if present)
- `stdout_callback = yaml` / `bin_ansible_callbacks = True` (clean, human-readable terminal output)

### 3.2 Inventory (`inventories/production/hosts.yml`)
Configured to support dual execution out-of-the-box:
```yaml
all:
  children:
    servers:
      hosts:
        server-prod:
          ansible_host: 127.0.0.1
          ansible_connection: local
          ansible_user: admin
          ansible_become: true
```
*Note: For remote execution, `ansible_host` can be overridden via command-line (`-e ansible_host=<remote_ip> -e ansible_connection=ssh`) or a dedicated remote inventory profile.*

### 3.3 Variable Hierarchy & Precedence
- **`group_vars/all.yml`**: Baseline variables applicable across all nodes (timezone, NTP servers, global package lists, Docker storage driver).
- **`group_vars/servers.yml`**: Server group configurations (system tuning, UFW port lists, docker compose directories).
- **`host_vars/server-prod/vars.yml`**: Host-specific variables that reference vault variables:
  ```yaml
  mysql_root_password: "{{ vault_mysql_root_password }}"
  cloudflared_token: "{{ vault_cloudflared_token }}"
  grafana_admin_password: "{{ vault_grafana_admin_password }}"
  syncthing_gui_password: "{{ vault_syncthing_gui_password }}"
  ```
- **`host_vars/server-prod/vault.yml`**: Encrypted with AES-256 storing raw secret strings prefixed with `vault_`.
- **`host_vars/server-prod/vault.yml.example`**: Plaintext dummy template for version control tracking.

---

## 4. Modular Roles Specification

### 4.1 Role: `common`
- **Purpose:** System baseline standardization and performance tuning.
- **Tasks:**
  - Synchronize timezone (`Asia/Jakarta`) and locales (`en_US.UTF-8`).
  - Update `apt` cache and install core packages (`curl`, `git`, `htop`, `jq`, `unzip`, `software-properties-common`, `ca-certificates`, `gnupg`).
  - Configure kernel tuning (`/etc/sysctl.d/99-server.conf`):
    - `vm.max_map_count = 262144` (required for search and logging engines).
    - `fs.file-max = 2097152`.
  - Configure `systemd-journald` retention (`SystemMaxUse=500M`) to prevent log volume saturation.
- **Handlers:**
  - `reload sysctl`
  - `restart systemd-journald`

### 4.2 Role: `security`
- **Purpose:** Host-level hardening without breaking existing SSH sessions or network services.
- **Tasks:**
  - SSH Hardening (`/etc/ssh/sshd_config.d/99-hardened.conf`):
    - Keep current port (`22`).
    - Disable root password login (`PermitRootLogin prohibit-password`).
    - Disable empty passwords (`PermitEmptyPasswords no`).
    - Max authentication attempts set to `5`.
  - UFW Firewall Configuration:
    - Default incoming: `deny`.
    - Default outgoing: `allow`.
    - Allow SSH (`22/tcp`).
    - Allow HTTP/HTTPS (`80/tcp`, `443/tcp`).
    - Allow internal network interface (`tailscale0`).
    - Enable UFW non-interactively.
  - Fail2ban Configuration:
    - Deploy `/etc/fail2ban/jail.local` with SSH jail enabled (`maxretry = 5`, `bantime = 1h`, `findtime = 10m`).
- **Handlers:**
  - `restart ssh`
  - `reload ufw`
  - `restart fail2ban`

### 4.3 Role: `docker`
- **Purpose:** Maintain the Docker CE runtime and plugins on Debian 13.
- **Tasks:**
  - Configure official Docker APT keyring and repository.
  - Install `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`.
  - Configure `/etc/docker/daemon.json`:
    - Log driver: `json-file` with `max-size: "50m"`, `max-file: "3"`.
    - `live-restore: true` (ensures containers remain running during daemon updates).
  - Ensure administrative users (`admin`, `sysadmin`) are members of the `docker` group.
- **Handlers:**
  - `restart docker`

### 4.4 Role: `docker_services`
- **Purpose:** Non-destructive lifecycle orchestration of core Docker stacks in `/srv/docker`.
- **Target Stacks:**
  - `nginx`: Global reverse proxy (ports 80, 443).
  - `mysql`: Database server (MySQL 8.4, port 3306).
  - `cloudflared`: Zero-trust Cloudflare tunnel.
  - `phpmyadmin`: DB administration UI (port 8080).
  - `portainer`: Container management UI (ports 9000, 9443).
  - `syncthing`: File synchronization service (ports 8384, 22000).
- **Adoption Mechanics:**
  - Pre-flight step checks if `/srv/docker/<stack>` exists.
  - Generates templated `docker-compose.yml` and `.env` files.
  - Runs `docker compose up -d` using Ansible's `community.docker.docker_compose_v2` module or `command` wrapper with change-detection.
  - Ensures existing data directories and persistent volumes are preserved.
- **Handlers:**
  - `reload global-nginx`
  - `restart compose stack`

### 4.5 Role: `monitoring`
- **Purpose:** Lifecycle management of the observability stack in `/opt/infra/monitoring`.
- **Components:**
  - `node-exporter`: Host metrics collector (port 9100).
  - `loki`: Log aggregation engine (port 3100).
  - `promtail`: Log shipping agent.
  - `grafana`: Metrics and logs visualization dashboard (port 3006).
- **Tasks:**
  - Ensure `/opt/infra/monitoring` directory structure and dashboard provisioning templates are maintained.
  - Manage docker compose lifecycle idempotently.

---

## 5. Playbook Structure & Execution Workflows

### 5.1 Playbooks
1. **`playbooks/site.yml`**: Master orchestration running all roles in sequence with granular tags (`common`, `security`, `docker`, `docker_services`, `monitoring`).
2. **`playbooks/bootstrap.yml`**: Initial bootstrap for fresh targets (installs python3, sudo, sets up sudoers).
3. **`playbooks/security.yml`**: Standalone security and firewall audits.
4. **`playbooks/services.yml`**: Standalone update cycle for docker container stacks.

### 5.2 Helper Scripts (`scripts/`)
- `run-local.sh`:
  Executes `ansible-playbook playbooks/site.yml` with `--connection=local` using the current inventory.
- `run-remote.sh`:
  Executes `ansible-playbook playbooks/site.yml` over SSH against a specified remote IP or hostname.
- `vault-manage.sh`:
  Interactive helper to encrypt, decrypt, view, or edit `vault.yml`.

---

## 6. Verification, Testing & Quality Gates

The implementation must pass the following verification gates before completion:

1. **Syntax Validation**:
   `ansible-playbook --syntax-check playbooks/site.yml`
   Must exit with code 0 and zero syntax errors.
2. **Linter & Style Validation**:
   Playbooks and roles must follow standard Ansible naming conventions, use fully qualified collection names (FQCN) where appropriate, and avoid deprecated syntax.
3. **Dry-Run Check (`--check --diff`)**:
   `ansible-playbook playbooks/site.yml --check --diff`
   Must preview changes safely without throwing unhandled exceptions.
4. **Live Execution & Idempotence Verification**:
   - First run applies missing configurations.
   - Second run:
     `ansible-playbook playbooks/site.yml`
     Must yield `changed=0 failed=0` (excluding inherently uncheckable non-stateful tasks).
5. **Container Continuity Verification**:
   `sudo docker ps` must confirm that `mysql`, `nginx`, `grafana`, and `cloudflared` remain healthy and active.

---

## 7. Architecture Mapping & Auditability (`docs/ARCHITECTURE.md`)

The repository will include `docs/ARCHITECTURE.md` detailing:
- Role dependency graph.
- Variable resolution tree.
- Guide for running codebase architecture inspections and zoom-out mapping.
