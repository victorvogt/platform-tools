# platform-tools

> Ansible-based infrastructure-as-code for a self-hosted homelab running on Scaleway.  
> Provisions a K3S cluster and deploys Gitea + Terrakube via Helm — fully automated, secrets managed with Ansible Vault.

---

## Overview

| Component | Description |
|-----------|-------------|
| **common** | Base OS setup: packages, timezone, hostname, SSH, admin user |
| **kubes** | K3S (lightweight Kubernetes) with kernel tuning and kubeconfig |
| **gitea** | Self-hosted Git service, deployed via Helm, daily S3 backups |
| **terrakube** | Terraform/OpenTofu workspace manager, deployed via Helm |

```
Scaleway VPS
└── K3S cluster
    ├── gitea namespace      ← Gitea (HTTP :3000 · SSH :2222)
    │   └── CronJob          ← Daily S3 backup at 03:00
    └── terrakube namespace  ← Terrakube API (:3100 → :8080)
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Ansible | ≥ 2.14 |
| `community.general` collection | latest |
| `ansible.posix` collection | latest |
| `kubernetes.core` collection | latest |
| SSH key at `~/.ssh/scaleway` | — |

Install collections:

```bash
ansible-galaxy collection install community.general ansible.posix kubernetes.core
```

---

## Repository structure

```
platform-tools/
├── ansible.cfg               # Ansible defaults (inventory, SSH, privilege escalation)
├── inventory.ini             # Host definitions
├── site.yml                  # Master playbook
├── group_vars/
│   └── all.yml               # Shared variables (timezone, DNS, NTP)
└── roles/
    ├── common/               # Base OS configuration
    ├── kubes/                # K3S installation
    ├── gitea/                # Gitea Helm deployment + S3 backup
    │   └── vars/
    │       ├── vault.yml             # Encrypted secrets (git-ignored)
    │       └── vault.yml.example     # Secret template
    └── terrakube/            # Terrakube Helm deployment
```

---

## Quick start

### 1. Configure your inventory

Edit `inventory.ini` with your server's IP address:

```ini
[homelab-gitlab]
my-server ansible_host=<YOUR_SERVER_IP> ansible_user=root
```

### 2. Set up secrets

Copy the vault template and fill in your credentials:

```bash
cp roles/gitea/vars/vault.yml.example roles/gitea/vars/vault.yml
```

```yaml
# roles/gitea/vars/vault.yml
vault_gitea_backup_s3_access_key: "your-access-key"
vault_gitea_backup_s3_secret_key: "your-secret-key"
vault_gitea_backup_s3_name:       "your-bucket-name"
vault_gitea_admin_username:       "admin"
vault_gitea_admin_password:       "strong-password"
vault_gitea_admin_email:          "admin@example.com"
```

Encrypt the vault file:

```bash
ansible-vault encrypt roles/gitea/vars/vault.yml
```

Save your vault password in `.vault_pass` (already listed in `.gitignore`):

```bash
echo "your-vault-password" > .vault_pass
```

### 3. Run the playbook

```bash
ansible-playbook site.yml
```

Or with the Docker helper (no local Ansible install required):

```bash
.docker/ansible-playbook.sh site.yml
```

---

## Roles

### `common`

Applies to all hosts. Ensures a consistent base configuration:

- Updates apt cache and installs essential packages (`curl`, `wget`, `vim`, `htop`, `git`, `unzip`, `net-tools`)
- Sets timezone (`Europe/Paris` by default), hostname, and NTP
- Ensures the admin user exists with `sudo` membership
- Enables and starts SSH

**Key variables** (`group_vars/all.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `timezone` | `Europe/Paris` | System timezone |
| `dns_servers` | `1.1.1.1`, `9.9.9.9` | DNS resolvers |
| `admin_user` | `root` | Admin account |

---

### `kubes`

Installs K3S on `homelab-gitlab` hosts:

1. Disables swap and removes it from `/etc/fstab`
2. Loads `br_netfilter` and `overlay` kernel modules (persisted)
3. Applies required sysctl parameters (`ip_forward`, `bridge-nf-call-iptables`)
4. Downloads and installs K3S via the official install script
5. Copies kubeconfig to `/root/.kube/config`

**Key variables** (`roles/kubes/defaults/main.yml`):

| Variable | Description |
|----------|-------------|
| `k3s_version` | K3S version to install (empty = latest) |
| `k3s_extra_args` | Extra flags passed to the K3S installer |
| `disable_swap` | Whether to disable swap (default: `true`) |

---

### `gitea`

Deploys [Gitea](https://gitea.io) on the K3S cluster using Helm:

1. Installs Helm if absent
2. Creates the `gitea` namespace
3. Adds the Gitea Helm chart repository
4. Templates `values.yml.j2` with Vault secrets and deploys with `helm upgrade --install`
5. Waits for the rollout to complete
6. Deploys a Kubernetes CronJob for daily S3 backups (runs at **03:00 UTC**)

**Key variables** (`roles/gitea/defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `gitea_namespace` | `gitea` | Kubernetes namespace |
| `gitea_helm_chart_version` | `""` | Pin a chart version (empty = latest) |
| `gitea_http_port` | `3000` | Gitea HTTP port |
| `gitea_ssh_port` | `2222` | Gitea SSH port |
| `gitea_domain` | `{{ ansible_host }}` | Access domain / IP |

**Backup** — the CronJob runs inside the cluster daily:

```
gitea dump  →  /tmp/gitea-dump.zip  →  s3://<bucket>/gitea-backup-YYYY-MM-DD.zip
```

S3 endpoint: `https://s3.fr-par.scw.cloud` (Scaleway Paris)

---

### `terrakube`

Deploys [Terrakube](https://terrakube.io) (open-source Terraform/OpenTofu workspace manager):

1. Installs Helm if absent
2. Creates the `terrakube` namespace
3. Adds the Terrakube Helm chart repository
4. Templates `values.yml.j2` and deploys with `helm upgrade --install`
5. Waits for `terrakube-api` deployment rollout

**Key variables** (`roles/terrakube/defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `terrakube_namespace` | `terrakube` | Kubernetes namespace |
| `terrakube_helm_chart_version` | `""` | Pin a chart version |
| `terrakube_postgres_storage` | `10Gi` | PostgreSQL PVC size |
| `terrakube_minio_storage` | `10Gi` | MinIO PVC size |
| `terrakube_service_port` | `3100` | Internal service port |
| `terrakube_host_port` | `8080` | External node port |
| `terrakube_domain` | `{{ ansible_host }}` | Access domain / IP |

---

## Secrets reference

All sensitive values are stored in `roles/gitea/vars/vault.yml` (encrypted with `ansible-vault`):

| Variable | Usage |
|----------|-------|
| `vault_gitea_backup_s3_access_key` | S3 credentials for backup |
| `vault_gitea_backup_s3_secret_key` | S3 credentials for backup |
| `vault_gitea_backup_s3_name` | S3 bucket name |
| `vault_gitea_admin_username` | Gitea admin account |
| `vault_gitea_admin_password` | Gitea admin password |
| `vault_gitea_admin_email` | Gitea admin email |

---

## Useful commands

```bash
# Run only a specific role
ansible-playbook site.yml --tags common
ansible-playbook site.yml --tags kubes
ansible-playbook site.yml --tags gitea

# Dry-run (check mode)
ansible-playbook site.yml --check

# Edit vault secrets
ansible-vault edit roles/gitea/vars/vault.yml

# View K3S node status on the remote
ansible homelab-gitlab -m command -a "k3s kubectl get nodes"

# View Gitea pods
ansible homelab-gitlab -m command -a "k3s kubectl -n gitea get pods"

# Manually trigger a backup job
ansible homelab-gitlab -m command -a \
  "k3s kubectl -n gitea create job --from=cronjob/gitea-s3-backup gitea-backup-manual"
```

---

## Security notes

- `.vault_pass` is **git-ignored** — never commit it.
- `roles/gitea/vars/vault.yml` is **git-ignored** — only the `.example` template is tracked.
- Temporary Helm values files (`/tmp/gitea-values.yml`, `/tmp/terrakube-values.yml`) are rendered on the remote host with mode `0600` and deleted after deployment.
- `host_key_checking` is disabled in `ansible.cfg` for convenience — consider enabling it in production.

