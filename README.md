# Hermes Agent Auto-Backup & Restore

Backup and restore your Hermes Agent config, skills, sessions, and memory to a local device (CT/VM/server) via SSH. No cloud involved.

> WARNING: You need your own backup device (a Linux server, container, or VM) on the same local network as your Hermes server. These scripts use direct SSH connections over your LAN. They will not work over the internet, to external servers, or without a dedicated device to store the backups.

---

## Quick Start

On a fresh Hermes server, run this and you're done:

```bash
curl -o setup-hermes.sh https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/setup-hermes.sh
bash setup-hermes.sh
```

**What it does:**
1. Ask for your backup device IP and test SSH connection
2. Restore existing backup (if available)
3. Save config so future backups know where to go
4. Set up automatic daily backup (you pick the time)
5. Optionally run the first backup right away

---

## Manual Setup

If you prefer to understand how it works:

### 1. Backup Script

```bash
# Download the backup script
curl -o ~/.hermes/scripts/hermes-backup.sh https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/hermes-backup.sh
chmod +x ~/.hermes/scripts/hermes-backup.sh

# Create config file — set your backup device IP
echo 'BACKUP_IP=192.168.1.100' > ~/.hermes/scripts/backup-target.conf
echo 'BACKUP_USER=root' >> ~/.hermes/scripts/backup-target.conf
```

### 2. Test

```bash
bash ~/.hermes/scripts/hermes-backup.sh
```

### 3. Schedule Daily Backup

```bash
hermes cron create \
  --name "hermes-backup" \
  --schedule "0 3 * * *" \
  --script hermes-backup.sh \
  --no-agent
```

> Cron uses your server's timezone. If your server is UTC, `0 19 * * *` = 3 AM WITA (Bali time).

---

## Restore

If your server dies or you need to move to a new one:

```bash
curl -o restore.sh https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/hermes-restore.sh
bash restore.sh
```

It will ask:
1. **Pick a backup** — choose from the list of folders on the backup device
2. **Target IP** — your new server's IP
3. **Confirm** — type RESTORE and you're done

---

## What Gets Backed Up

| Item | Description | Remote Backup | Local Archive |
|------|-------------|---------------|---------------|
| config.yaml | Provider & tool settings | Yes | Yes |
| skills/ | Custom skills & workflows | Yes | Yes |
| .env | API keys & secrets | Yes (via SSH) | Yes |
| auth.json | Authentication tokens | Yes (via SSH) | Yes |
| state.db | Chat history & sessions | Yes | Yes |
| mnemosyne/ | Long-term memory | Yes | No |
| cron/ | Scheduled jobs | Yes | No |
| Hermes source | Agent source code | Yes | No |

All files live under `/root/backups/<hostname>/` on the backup device.

---

## Multiple Servers

Same script works on every Hermes server. Add each server's SSH key to the backup device and each one automatically gets its own folder by hostname.

---

## Security

- Everything stays on your local network
- SSH key authentication only — no passwords
- rsync over SSH tunnel (encrypted)

---

## License

MIT
