#!/bin/bash
# Hermes Agent Auto-Backup to Local Backup Device
# =================================================
# Change BACKUP_IP to match your backup device's IP address.
# Setup: Place in ~/.hermes/scripts/hermes-backup.sh
# Schedule: hermes cron create --name hermes-backup --schedule "0 19 * * *" --script ~/.hermes/scripts/hermes-backup.sh --no-agent
#
# CONFIGURATION — Change these:
BACKUP_IP="10.10.10.116"          # Your backup device IP
BACKUP_DIR="/root/hermes-backup"  # Destination folder on backup device

# — Don't change below this line unless you know what you're doing —
HERMES_HOME="$HOME/.hermes"
HERMES_SRC="/usr/local/lib/hermes-agent"
DATE=$(date +%Y-%m-%d)
FILENAME="hermes-backup-$DATE.tar.gz"
MAX_LOCAL=7

echo "[$(date '+%H:%M:%S')] === Hermes Backup $DATE ==="

# ===== BACKUP TO REMOTE DEVICE =====
echo "[1/3] Backing up to $BACKUP_IP..."

ssh root@$BACKUP_IP "mkdir -p $BACKUP_DIR/config $BACKUP_DIR/sessions $BACKUP_DIR/skills $BACKUP_DIR/mnemosyne $BACKUP_DIR/cron $BACKUP_DIR/hermes-src" 2>/dev/null

rsync -a "$HERMES_HOME/config.yaml" "root@$BACKUP_IP:$BACKUP_DIR/config/" 2>/dev/null && echo "  [OK] config.yaml"
rsync -a "$HERMES_HOME/.env" "root@$BACKUP_IP:$BACKUP_DIR/config/" 2>/dev/null && echo "  [OK] .env"
rsync -a "$HERMES_HOME/auth.json" "root@$BACKUP_IP:$BACKUP_DIR/config/" 2>/dev/null && echo "  [OK] auth.json"
rsync -a "$HERMES_HOME/state.db" "root@$BACKUP_IP:$BACKUP_DIR/sessions/" 2>/dev/null && echo "  [OK] state.db"
rsync -a --delete "$HERMES_HOME/skills/" "root@$BACKUP_IP:$BACKUP_DIR/skills/" 2>/dev/null && echo "  [OK] skills/"
rsync -a --delete "$HERMES_HOME/mnemosyne/" "root@$BACKUP_IP:$BACKUP_DIR/mnemosyne/" 2>/dev/null && echo "  [OK] mnemosyne/"
rsync -a "$HERMES_HOME/cron/" "root@$BACKUP_IP:$BACKUP_DIR/cron/" 2>/dev/null && echo "  [OK] cron/"

# Optional: backup Hermes source (exclude heavy/dev dirs)
rsync -a --delete \
  --exclude='.git' --exclude='node_modules' --exclude='venv' --exclude='.venv' \
  --exclude='__pycache__' --exclude='*.pyc' \
  "$HERMES_SRC/" "root@$BACKUP_IP:$BACKUP_DIR/hermes-src/" 2>/dev/null && echo "  [OK] hermes source"

# ===== FULL LOCAL ARCHIVE =====
echo "[2/3] Creating local archive..."
FILES=()
for f in config.yaml .env state.db auth.json; do
    [ -f "$HERMES_HOME/$f" ] && FILES+=("$HERMES_HOME/$f")
done
[ -d "$HERMES_HOME/skills" ] && FILES+=("$HERMES_HOME/skills")

if [ ${#FILES[@]} -gt 0 ]; then
    tar -czf "/root/$FILENAME" "${FILES[@]}" 2>/dev/null && \
    echo "  [OK] /root/$FILENAME ($(du -h /root/$FILENAME | cut -f1))"
fi

# Clean old archives
echo "[3/3] Cleaning old archives..."
ls -1t /root/hermes-backup-*.tar.gz 2>/dev/null | \
    tail -n +$((MAX_LOCAL+1)) | xargs rm -f 2>/dev/null
echo "  [OK] Keeping last $MAX_LOCAL archives"

echo "[$(date '+%H:%M:%S')] === Backup Complete ==="
