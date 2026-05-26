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
- **Backup device** — any Linux server/CT/VM reachable via SSH (can be a Proxmox LXC)
- SSH key-based auth between Hermes server and backup device

## Setup

### 1. Create a Backup Device

Spin up a lightweight Linux server/container (e.g., Ubuntu 24.04, 1GB RAM, 20GB disk). Give it a static IP on your local network. Set a root password.

### 2. SSH Key Setup

On your **Hermes server**, generate an SSH key if you don't have one:

```bash
ssh-keygen -t ed25519 -N ""
```

Copy the public key to the backup device:

```bash
ssh-copy-id root@<BACKUP_IP>
```

Or manually:

```bash
cat ~/.ssh/id_ed25519.pub | ssh root@<BACKUP_IP> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

Test it:

```bash
ssh root@<BACKUP_IP> "echo connected"
```

### 3. Create the Backup Directory

On the backup device:

```bash
ssh root@<BACKUP_IP> "mkdir -p /root/hermes-backup"
```

### 4. Create the Backup Script

Create `~/.hermes/scripts/hermes-backup.sh` — copy the template below and change `BACKUP_IP` to your backup device's IP:

```bash
#!/bin/bash
# Hermes Agent Auto-Backup to Local Backup Device
# Change BACKUP_IP to match your backup device

HERMES_HOME="$HOME/.hermes"
BACKUP_IP="10.10.10.116"
BACKUP_DIR="/root/hermes-backup"
HERMES_SRC="/usr/local/lib/hermes-agent"
DATE=$(date +%Y-%m-%d)
FILENAME="hermes-backup-$DATE.tar.gz"
MAX_LOCAL=7

echo "[$(date '+%H:%M:%S')] === Hermes Backup $DATE ==="

# ===== BACKUP TO REMOTE DEVICE =====
echo "[1] Backing up to $BACKUP_IP..."

rsync -a "$HERMES_HOME/config.yaml" "root@$BACKUP_IP:$BACKUP_DIR/config/" 2>/dev/null
rsync -a "$HERMES_HOME/.env" "root@$BACKUP_IP:$BACKUP_DIR/config/" 2>/dev/null
rsync -a "$HERMES_HOME/auth.json" "root@$BACKUP_IP:$BACKUP_DIR/config/" 2>/dev/null
rsync -a "$HERMES_HOME/state.db" "root@$BACKUP_IP:$BACKUP_DIR/sessions/" 2>/dev/null
rsync -a --delete "$HERMES_HOME/skills/" "root@$BACKUP_IP:$BACKUP_DIR/skills/" 2>/dev/null
rsync -a --delete "$HERMES_HOME/mnemosyne/" "root@$BACKUP_IP:$BACKUP_DIR/mnemosyne/" 2>/dev/null
rsync -a "$HERMES_HOME/cron/" "root@$BACKUP_IP:$BACKUP_DIR/cron/" 2>/dev/null

# Optional: backup Hermes source (exclude .git/venv)
rsync -a --delete \
  --exclude='.git' --exclude='node_modules' --exclude='venv' --exclude='.venv' \
  --exclude='__pycache__' --exclude='*.pyc' \
  "$HERMES_SRC/" "root@$BACKUP_IP:$BACKUP_DIR/hermes-src/" 2>/dev/null

# ===== FULL LOCAL ARCHIVE (redundancy) =====
echo "[2] Creating local archive..."
FILES=()
for f in config.yaml .env state.db auth.json; do
    [ -f "$HERMES_HOME/$f" ] && FILES+=("$HERMES_HOME/$f")
done
[ -d "$HERMES_HOME/skills" ] && FILES+=("$HERMES_HOME/skills")

if [ ${#FILES[@]} -gt 0 ]; then
    tar -czf "/root/$FILENAME" "${FILES[@]}" 2>/dev/null
fi

# Clean old archives
ls -1t /root/hermes-backup-*.tar.gz 2>/dev/null | \
    tail -n +$((MAX_LOCAL+1)) | xargs rm -f 2>/dev/null

echo "[$(date '+%H:%M:%S')] === Backup Complete ==="
```

Make it executable:

```bash
chmod +x ~/.hermes/scripts/hermes-backup.sh
```

### 5. Schedule with Cron

The cron schedule uses your **server's local timezone**. Pick a time when the server is idle (e.g., early morning):

```bash
# Example: backup daily at 3 AM (server local time)
hermes cron create \
  --name "hermes-backup" \
  --schedule "0 3 * * *" \
  --script ~/.hermes/scripts/hermes-backup.sh \
  --no-agent
```

> 💡 **Timezone tip:** If your server is in UTC but you want backup at 3 AM WITA/Bali (+08:00), use `"0 19 * * *"` (19:00 UTC = 03:00 WITA next day). Check your timezone with `timedatectl`.

### 6. Test It

```bash
bash ~/.hermes/scripts/hermes-backup.sh
```

Check the backup device:

```bash
ssh root@<BACKUP_IP> "du -sh /root/hermes-backup"
```

## Restore

On a **fresh Hermes installation**, run from the Hermes server:

```bash
# Restore everything from backup device
rsync -a root@<BACKUP_IP>:/root/hermes-backup/config/config.yaml ~/.hermes/
rsync -a root@<BACKUP_IP>:/root/hermes-backup/config/.env ~/.hermes/
rsync -a root@<BACKUP_IP>:/root/hermes-backup/config/auth.json ~/.hermes/
rsync -a root@<BACKUP_IP>:/root/hermes-backup/sessions/state.db ~/.hermes/
rsync -a --delete root@<BACKUP_IP>:/root/hermes-backup/skills/ ~/.hermes/skills/
rsync -a --delete root@<BACKUP_IP>:/root/hermes-backup/mnemosyne/ ~/.hermes/mnemosyne/
```

Or from local archive:

```bash
tar -xzf /root/hermes-backup-YYYY-MM-DD.tar.gz -C ~/
```

## Security Notes

- Everything stays on **your local network** — zero cloud exposure
- Backup device should be on the same LAN for speed
- The local `.tar.gz` archive is on your server only — clean old ones with `rm /root/hermes-backup-*.tar.gz`

## What to Expect

Every day at your scheduled time:
1. All Hermes config, skills, sessions, memory backed up to the remote device via rsync
2. Full archive (including `.env`) saved locally at `/root/hermes-backup-YYYY-MM-DD.tar.gz`
3. Local archives older than 7 days auto-cleaned
4. Backup device holds the full Hermes source for total recovery

## License

MIT
