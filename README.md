# Ansible Infrastructure Automation (`ansible-fyodor-aws`)

[![Ansible Core](https://img.shields.io/badge/Ansible-2.19+-red.svg)](https://docs.ansible.com/)
[![OS](https://img.shields.io/badge/Debian-13%20(Trixie)-blue.svg)](https://www.debian.org/)
[![License](https://img.shields.io/badge/License-Private-lightgrey.svg)]()

Repositori automasi infrastruktur server berbasis **Ansible (Core 2.19+)** yang mengadopsi standar arsitektur *enterprise best practices* (modular roles, multi-environment inventories, enkripsi Ansible Vault, dan idempotensi 100%).

Repositori ini dirancang khusus untuk mengelola:
- **Base OS & System Tuning**: Timezone (`Asia/Jakarta`), locale, paket esensial, kernel tuning sysctl, dan batas log journald.
- **Security Hardening**: SSH hardening drop-in, UFW firewall (*default deny incoming* dengan *whitelist* SSH, Web, Tailscale), serta proteksi brute-force Fail2ban.
- **Docker Runtime**: Instalasi resmi Docker CE Debian 13, plugin Docker Compose, dan daemon log-rotation dengan `live-restore: true`.
- **Core Docker Stacks (`/srv/docker`)**: Manajemen non-destruktif tumpukan container aktif (Nginx global reverse proxy, MySQL 8.4, Cloudflared tunnel, phpMyAdmin, Portainer, Syncthing).
- **Monitoring & Observability (`/opt/infra/monitoring`)**: Stack Prometheus Node-Exporter, Grafana (port 3006), Loki, dan Promtail.

---

## Daftar Isi

1. [Struktur Repositori](#struktur-repositori)
2. [Prasyarat Sistem](#prasyarat-sistem)
3. [Panduan Konfigurasi & Variabel](#panduan-konfigurasi--variabel)
4. [Pengelolaan Rahasia (Ansible Vault)](#pengelolaan-rahasia-ansible-vault)
5. [Panduan Eksekusi Playbook](#panduan-eksekusi-playbook)
6. [Penggunaan Tags](#penggunaan-tags)
7. [Skrip Helper Operator](#skrip-helper-operator)
8. [Verifikasi, Dry-Run & Idempotensi](#verifikasi-dry-run--idempotensi)
9. [Panduan Perintah AI Agent (/zoom-out & /improve)](#panduan-perintah-ai-agent)
10. [Prinsip Keamanan & Non-Destructive Adoption](#prinsip-keamanan--non-destructive-adoption)

---

## Struktur Repositori

```text
.
├── ansible.cfg                             # Konfigurasi default runtime Ansible
├── .gitignore                              # Proteksi kebocoran secrets (*.vault_pass, vault.yml)
├── README.md                               # Panduan lengkap operasional repositori
├── inventories/
│   ├── production/                         # Lingkungan Produksi
│   │   ├── hosts.yml                       # Target host (dukungan hybrid local/SSH)
│   │   ├── group_vars/
│   │   │   ├── all.yml                     # Variabel global (timezone, paket dasar)
│   │   │   └── servers.yml                 # Variabel server (sysctl, journald)
│   │   └── host_vars/
│   │       └── server-prod/
│   │           ├── vars.yml                # Variabel host & mapping vault
│   │           ├── vault.yml               # Variabel rahasia terenkripsi (di-ignore git)
│   │           └── vault.yml.example       # Template rahasia aman di-commit
│   └── staging/                            # Template untuk server staging masa depan
├── playbooks/
│   ├── site.yml                            # Master orchestrator seluruh sistem
│   ├── bootstrap.yml                       # Setup minimal host baru (Python & sudo)
│   ├── security.yml                        # Standalone hardening OS, SSH & Firewall
│   └── services.yml                        # Standalone deploy container Docker & Monitoring
├── roles/
│   ├── common/                             # Role paket dasar, locale & sysctl
│   ├── security/                           # Role SSH, UFW firewall & Fail2ban
│   ├── docker/                             # Role runtime Docker CE engine & Compose
│   ├── docker_services/                    # Role orkestrasi container /srv/docker
│   └── monitoring/                         # Role orkestrasi stack /opt/infra/monitoring
├── scripts/
│   ├── run-local.sh                        # Eksekusi langsung di server lokal
│   ├── run-remote.sh                       # Eksekusi via SSH dari mesin luar
│   └── vault-manage.sh                     # Helper CLI Ansible Vault (init, edit, view, decrypt)
└── docs/
    ├── ARCHITECTURE.md                     # Peta arsitektur detail & panduan refaktor
    └── superpowers/                        # Spesifikasi desain & rencana implementasi
```

---

## Prasyarat Sistem

1. **Sistem Operasi Target**: Debian GNU/Linux 13 (Trixie) atau Debian 12 (Bookworm).
2. **Ansible**: Ansible Core 2.16+ (Disarankan 2.19+).
3. **Python**: Python 3.10+ di host controller maupun target node.
4. **Koleksi Ansible**:
   ```bash
   ansible-galaxy collection install community.general community.docker
   ```
5. **Akses Privilese**: User dengan hak akses `sudo` tanpa password (`admin` / `sysadmin`).

---

## Panduan Konfigurasi & Variabel

Struktur variabel menganut prinsip hierarki *Ansible Variable Precedence*:

### 1. Konfigurasi Global (`inventories/production/group_vars/all.yml`)
Menampung konfigurasi universal yang berlaku di semua server:
```yaml
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
  - rsync
  - tree
```

### 2. Konfigurasi Server Group (`inventories/production/group_vars/servers.yml`)
Menampung parameter kernel sysctl dan retensi log:
```yaml
sysctl_settings:
  vm.max_map_count: 262144        # Kebutuhan Loki & Elasticsearch
  fs.file-max: 2097152
  net.core.somaxconn: 65535
journald_max_use: "500M"          # Mencegah log systemd memenuhi disk
```

### 3. Pemetaan Variabel Host (`inventories/production/host_vars/server-prod/vars.yml`)
Menghubungkan variabel terbuka ke variabel rahasia Ansible Vault dengan fallback aman:
```yaml
mysql_root_password: "{{ vault_mysql_root_password | default('CHANGE_ME_IN_VAULT') }}"
cloudflared_token: "{{ vault_cloudflared_token | default('') }}"
grafana_admin_password: "{{ vault_grafana_admin_password | default('admin') }}"
syncthing_gui_password: "{{ vault_syncthing_gui_password | default('') }}"
```

---

## Pengelolaan Rahasia (Ansible Vault)

Seluruh password, token, dan kunci privat wajib disimpan di file terenkripsi `vault.yml` dan tidak boleh di-commit dalam bentuk plaintext ke Git.

### 1. Inisialisasi File Vault
Salin template `vault.yml.example` menjadi `vault.yml` lalu enkripsi dengan script helper:
```bash
./scripts/vault-manage.sh init
```
*Script akan membuat file `vault.yml` dan meminta Anda memasukkan password enkripsi baru.*

### 2. Mengedit & Melihat Isi Vault
```bash
# Mengedit file vault (akan membuka teks editor default)
./scripts/vault-manage.sh edit

# Melihat isi file vault tanpa mengubah
./scripts/vault-manage.sh view

# Mendekripsi file vault kembali ke plaintext (untuk maintenance)
./scripts/vault-manage.sh decrypt
```

### 3. Struktur Variabel di dalam `vault.yml`
Pastikan variabel di dalam `vault.yml` selalu diawali dengan prefix `vault_`:
```yaml
vault_mysql_root_password: "PasswordDBSuperRahasia123!"
vault_cloudflared_token: "eyJh......"
vault_grafana_admin_password: "PasswordGrafanaKuat"
vault_syncthing_gui_password: "PasswordSyncthingKuat"
```

### 4. Menggunakan Password File (`.vault_pass`)
Agar tidak perlu mengetik password setiap kali menjalankan playbook:
```bash
echo "PasswordVaultAnda" > .vault_pass
chmod 600 .vault_pass
```
*Catatan: File `.vault_pass` sudah otomatis masuk ke dalam `.gitignore`.*

---

## Panduan Eksekusi Playbook

### 1. Eksekusi Lokal di Server (Self-Managing)
Gunakan helper script [`run-local.sh`](file:///home/admin/ansible-infra/scripts/run-local.sh) atau jalankan perintah langsung:
```bash
# Menggunakan helper script
./scripts/run-local.sh

# Atau perintah langsung
ansible-playbook playbooks/site.yml -i inventories/production/hosts.yml --ask-vault-pass
```

### 2. Eksekusi Remote via SSH (Dari Laptop / CI-CD)
Gunakan helper script [`run-remote.sh`](file:///home/admin/ansible-infra/scripts/run-remote.sh):
```bash
# Sintaks: ./scripts/run-remote.sh <IP_ATAU_HOSTNAME> [opsi tambahan]
./scripts/run-remote.sh 172.31.16.206 -u admin --ask-vault-pass
```

### 3. Menjalankan Sub-Playbook Spesifik
Jika Anda hanya ingin melakukan update pada bagian tertentu tanpa mengeksekusi master playbook:
```bash
# Hanya setup awal dependensi Python & sudo di host baru
ansible-playbook playbooks/bootstrap.yml

# Hanya update security hardening (SSH drop-in, UFW rules, Fail2ban)
ansible-playbook playbooks/security.yml

# Hanya deploy/update container Docker dan Monitoring stack
ansible-playbook playbooks/services.yml
```

---

## Penggunaan Tags

Master playbook [`playbooks/site.yml`](file:///home/admin/ansible-infra/playbooks/site.yml) dilengkapi tags terstruktur untuk eksekusi yang cepat dan terarah:

| Tag | Cakupan Eksekusi | Keterangan |
|---|---|---|
| `common` / `base` | Role `common` | Update repositori, paket OS dasar, sysctl tuning |
| `security` | Role `security` | SSH hardening, firewall UFW, aktivasi Fail2ban |
| `docker` | Role `docker` | Engine Docker CE, Compose plugin, daemon.json |
| `docker_services` / `services` | Role `docker_services` | Stack container di `/srv/docker` |
| `monitoring` | Role `monitoring` | Stack Prometheus node-exporter, Grafana, Loki |

**Contoh Perintah Penggunaan Tags:**
```bash
# Hanya memperbarui aturan firewall dan SSH
ansible-playbook playbooks/site.yml --tags "security"

# Hanya memperbarui Docker engine dan container services
ansible-playbook playbooks/site.yml --tags "docker,services"

# Menjalankan seluruh sistem KECUALI monitoring
ansible-playbook playbooks/site.yml --skip-tags "monitoring"
```

---

## Skrip Helper Operator

Semua script berada di folder [`scripts/`](file:///home/admin/ansible-infra/scripts/) dan sudah memiliki permission eksekusi (`chmod +x`):

1. **`./scripts/run-local.sh [options]`**
   Menjalankan `site.yml` langsung di server target dengan koneksi lokal (`ansible_connection=local`). Menerima semua parameter standar `ansible-playbook` (misal `--check`, `--tags`).
2. **`./scripts/run-remote.sh <target-ip> [options]`**
   Menjalankan `site.yml` dari mesin luar me-remote server via SSH.
3. **`./scripts/vault-manage.sh {init|edit|view|decrypt}`**
   Manajemen praktis file rahasia Ansible Vault tanpa perlu menghafal path file.

---

## Verifikasi, Dry-Run & Idempotensi

Sebelum menerapkan perubahan secara permanen pada server produksi, selalu lakukan prosedur verifikasi berikut:

### 1. Pengecekan Sintaksis (*Syntax Check*)
```bash
ansible-playbook --syntax-check playbooks/*.yml
```
*Memastikan seluruh YAML, template Jinja, dan FQCN modul valid.*

### 2. Simulasi / Dry-Run Mode (`--check --diff`)
```bash
ansible-playbook playbooks/site.yml --check --diff
```
*Ansible akan menyimulasikan eksekusi dan menampilkan 'diff' teks perubahan tanpa menyentuh sistem atau me-restart container.*

### 3. Pengecekan Idempotensi Penuh
Jalankan playbook dua kali berturut-turut. Pada eksekusi kedua, output harus menunjukkan `changed=0 failed=0`:
```text
PLAY RECAP *********************************************************************
server-prod                : ok=28   changed=0    unreachable=0    failed=0
```

---

## Panduan Perintah AI Agent

Repositori ini dioptimalkan untuk navigasi dan refaktor oleh Agen AI (seperti Google Antigravity / Gemini CLI):

### 1. Perintah `/zoom-out` (Codebase Architecture Mapping)
Jika Anda atau Agen AI ingin memetakan relasi antar host, variabel, dan peran:
```bash
# 1. Peta grafis hirarki inventaris dan variabel
ansible-inventory -i inventories/production/hosts.yml --graph --vars

# 2. Peta alur eksekusi task dan role master playbook
ansible-playbook playbooks/site.yml --list-tasks --list-tags

# 3. Struktur pohon dependensi file
tree -I ".git|.superpowers" roles/ inventories/ playbooks/
```

### 2. Perintah `/improve-codebase-architecture` (Audit & Refactoring)
Gunakan panduan di [`docs/ARCHITECTURE.md`](file:///home/admin/ansible-infra/docs/ARCHITECTURE.md) untuk melakukan audit:
- **Deteksi Hardcoded Secret**: Pastikan tidak ada string password/token di file `.yml` selain `vault.yml`.
- **Ekstraksi Role Baru**: Pisahkan task berulang menjadi role mandiri di bawah `roles/<nama_role>/`.
- **Enkapsulasi Variabel**: Pindahkan variabel default ke `roles/<role>/defaults/main.yml`.

---

## Prinsip Keamanan & Non-Destructive Adoption

1. **Zero Data Loss Guarantee**:
   Task pada role `docker_services` mengadopsi volume persistent dan container yang sedang berjalan secara *in-place*. File data MySQL, konfigurasi Nginx, dan persistent store Grafana tidak akan terhapus.
2. **Uptime Preservation via `live-restore`**:
   Docker daemon dikonfigurasi dengan `"live-restore": true`, sehingga reload konfigurasi daemon tidak akan mematikan container yang sedang melayani traffic.
3. **Pencegahan SSH Lockout**:
   Aturan firewall UFW menerapkan pembukaan port SSH (`22/tcp`) dan antarmuka `tailscale0` *sebelum* layanan firewall diaktifkan (`state: enabled`).
4. **Strict Secret Hygiene**:
   File contoh rahasia menggunakan format `vault.yml.example` agar parser inventaris Ansible tidak memuat nilai dummy secara tidak sengaja.
