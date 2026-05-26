# How to Auto-Backup Hermes Agent to a Local Backup Device

Step-by-step guide to backup your **Hermes Agent** configuration, skills, sessions, memory, and source code to a **dedicated backup device** (CT/VM/server) on your local network every day. No GitHub, no cloud, no third party.

## What This Backs Up

| Item | Description | To Backup Device? | Local Archive? |
|------|-------------|-------------------|----------------|
| `config.yaml` | Provider settings, tools, integrations | ✅ Yes | ✅ Yes |
| `skills/` | Your custom skills and workflows | ✅ Yes | ✅ Yes |
| `.env` | API keys & secrets | ✅ Yes (SSH/rsync) | ✅ Yes |
| `auth.json` | Authentication tokens | ✅ Yes (SSH/rsync) | ✅ Yes |
| `state.db` | Session transcripts & chat history | ✅ Yes | ✅ Yes |
| `mnemosyne/` | Agent's long-term memory | ✅ Yes | ❌ External only |
| `cron/` | Scheduled jobs & scripts | ✅ Yes | ❌ External only |
| Hermes source | Hermes Agent code itself | ✅ Yes | ❌ External only |

> 🔒 **Security:** Everything stays on your local network. No data ever leaves your infrastructure.

## Requirements

- **Hermes Agent** installed on your main server
- **Backup device** — any Linux server/CT/VM reachable via SSH (e.g., a Proxmox LXC)
- SSH key-based auth between Hermes server and backup device

---

## Quick Setup

### 1. Create a Backup Device

Spin up a lightweight Linux container/server (e.g., Ubuntu 24.04, 1GB RAM, 20GB disk). Give it a static IP on your local network.

### 2. SSH Key Setup

On your **Hermes server**, generate an SSH key and copy it to the backup device:

```bash
ssh-keygen -t ed25519 -N ""
ssh-copy-id root@<BACKUP_IP>
```

Test it:

```bash
ssh root@<BACKUP_IP> "echo connected"
```

### 3. Install the Backup Script

Create `~/.hermes/scripts/hermes-backup.sh` with the script from this repo, or download it:

```bash
curl -o ~/.hermes/scripts/hermes-backup.sh https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/hermes-backup.sh
chmod +x ~/.hermes/scripts/hermes-backup.sh
```

### 4. Configure Backup Target

Create `~/.hermes/scripts/backup-target.conf`:

```bash
echo 'BACKUP_IP=<YOUR_BACKUP_DEVICE_IP>' > ~/.hermes/scripts/backup-target.conf
echo 'BACKUP_USER=root' >> ~/.hermes/scripts/backup-target.conf
```

### 5. Test It

```bash
bash ~/.hermes/scripts/hermes-backup.sh
```

Check the backup device:

```bash
ssh root@<BACKUP_IP> "du -sh /root/backups/*/"
```

### 6. Schedule with Cron

```bash
hermes cron create \
  --name "hermes-backup" \
  --schedule "0 3 * * *" \
  --script hermes-backup.sh \
  --no-agent
```

> 💡 **Timezone tip:** Cron uses your server's local timezone. If your server is in UTC, use `0 19 * * *` for 3 AM Bali time (WITA, UTC+8). Check with `timedatectl`.

---

## How It Works

**The backup script is universal** — same script works on any Hermes server. It automatically:

1. Reads the backup device IP from `~/.hermes/scripts/backup-target.conf`
2. Creates a folder on the backup device named after the server's hostname
3. Rsyncs all Hermes files to that folder
4. Creates a local `.tar.gz` archive as secondary redundancy
5. Cleans up archives older than 7 days

**Backup structure on the backup device:**
```
/root/backups/<hostname>/
├── config/         config.yaml, .env, auth.json
├── skills/         all skills & workflows
├── sessions/       state.db (chat history)
├── cron/           scheduled jobs
├── mnemosyne/      long-term memory
└── hermes-src/     Hermes agent source code
```

**Multiple backup options:**
```bash
# Using config file (default)
bash hermes-backup.sh

# Using command-line IP (one-off)
bash hermes-backup.sh <YOUR_BACKUP_DEVICE_IP>

# Using environment variable
BACKUP_IP=<YOUR_BACKUP_DEVICE_IP> bash hermes-backup.sh
```

---

## Setting Up Multiple Hermes Servers

For each Hermes server you want to back up:

1. Install the script and config (same 2 files on each server)
2. Add each server's SSH key to the backup device
3. Schedule the cron job

Each server automatically gets its own folder: `/root/backups/<hostname>/`

No duplicate scripts, no hardcoded paths — configure once per server.

---

## Restore

On a **fresh Hermes installation**, run the restore script from any machine that has SSH access to both the backup device and the target server:

```bash
# Download restore script
curl -o restore.sh https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/hermes-restore.sh

# Run it
bash restore.sh
```

You'll be prompted to:
1. Select which backup to restore (by hostname)
2. Enter the target server IP address
3. Confirm — everything is restored automatically

Or manually:

```bash
rsync -a root@<BACKUP_IP>:/root/backups/<hostname>/config/config.yaml ~/.hermes/
rsync -a root@<BACKUP_IP>:/root/backups/<hostname>/config/.env ~/.hermes/
rsync -a root@<BACKUP_IP>:/root/backups/<hostname>/config/auth.json ~/.hermes/
rsync -a root@<BACKUP_IP>:/root/backups/<hostname>/sessions/state.db ~/.hermes/
rsync -a --delete root@<BACKUP_IP>:/root/backups/<hostname>/skills/ ~/.hermes/skills/
rsync -a --delete root@<BACKUP_IP>:/root/backups/<hostname>/mnemosyne/ ~/.hermes/mnemosyne/
```

Or from local archive:

```bash
tar -xzf /root/hermes-backup-*.tar.gz -C ~/
```

---

## Security Notes

- Everything stays on **your local network** — zero cloud exposure
- Backup device should be on the same LAN for speed
- The local `.tar.gz` archive is on your server only — clean old ones with `rm /root/hermes-backup-*.tar.gz`

## License

MIT
