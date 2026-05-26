#!/bin/bash
# Hermes Agent Auto-Backup — Universal
# Bisa dipake di Hermes mana aja, backup ke device mana aja.
#
# Cara pake:
#   bash hermes-backup.sh                                              # pake config file
#   bash hermes-backup.sh <BACKUP_DEVICE_IP>                           # pake IP langsung
#   bash hermes-backup.sh <BACKUP_DEVICE_IP> <FOLDER_NAME>             # IP + nama folder custom
#   BACKUP_IP=192.168.1.100 BACKUP_FOLDER=my-server bash hermes-backup.sh  # pake env var
#
# Config file: ~/.hermes/scripts/backup-target.conf
#   BACKUP_IP=192.168.1.100
#   BACKUP_USER=root
#   BACKUP_FOLDER=my-server          # optional, default = hostname server
#
# Schedule: hermes cron create --name hermes-backup --script hermes-backup.sh --no-agent

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ===== CONFIG — cari IP tujuan & nama folder =====
CONFIG_FILE="$HOME/.hermes/scripts/backup-target.conf"

if [ -n "$2" ]; then
    BACKUP_IP="$1"
    BACKUP_FOLDER="$2"
elif [ -n "$1" ]; then
    BACKUP_IP="$1"
elif [ -n "$BACKUP_IP" ] && [ -n "$BACKUP_FOLDER" ]; then
    :  # keduanya dari env var
elif [ -n "$BACKUP_IP" ]; then
    :  # IP dari env, folder pake hostname
elif [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ Gak tau mau backup ke mana!"
    echo "   Cara 1: bash hermes-backup.sh <IP_BACKUP_DEVICE> [NAMA_FOLDER]"
    echo "   Cara 2: buat file $CONFIG_FILE isi:"
    echo "     BACKUP_IP=192.168.1.100"
    echo "     BACKUP_FOLDER=my-server"
    exit 1
fi

BACKUP_USER="${BACKUP_USER:-root}"
BACKUP_CT="${BACKUP_USER}@${BACKUP_IP}"
BACKUP_FOLDER="${BACKUP_FOLDER:-$(hostname -s)}"
BACKUP_DIR="/root/backups/$BACKUP_FOLDER"

HERMES_HOME="$HOME/.hermes"
HERMES_SRC="/usr/local/lib/hermes-agent"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
FILENAME="hermes-backup-$BACKUP_FOLDER-$DATE.tar.gz"
MAX_LOCAL=7

START_TS=$(date +%s)

echo "======= HERMES BACKUP ======="
echo "Folder:    $BACKUP_FOLDER"
echo "Date:      $DATE"
echo "Target:    $BACKUP_CT:$BACKUP_DIR"
echo ""

# ===== 1. RSYNC to backup device =====
echo "[1/5] Backing up config & state..."

ssh -n "$BACKUP_CT" "mkdir -p $BACKUP_DIR/config $BACKUP_DIR/skills $BACKUP_DIR/sessions $BACKUP_DIR/cron $BACKUP_DIR/mnemosyne $BACKUP_DIR/hermes-src" 2>/dev/null

rsync -a --delete "$HERMES_HOME/config.yaml" "$BACKUP_CT:$BACKUP_DIR/config/" 2>/dev/null && echo "  [OK] config.yaml"
rsync -a --delete "$HERMES_HOME/skills/" "$BACKUP_CT:$BACKUP_DIR/skills/" 2>/dev/null && echo "  [OK] skills/"
rsync -a "$HERMES_HOME/state.db" "$BACKUP_CT:$BACKUP_DIR/sessions/" 2>/dev/null && echo "  [OK] state.db"
rsync -a "$HERMES_HOME/.env" "$BACKUP_CT:$BACKUP_DIR/config/" 2>/dev/null && echo "  [OK] .env"
rsync -a "$HERMES_HOME/auth.json" "$BACKUP_CT:$BACKUP_DIR/config/" 2>/dev/null && echo "  [OK] auth.json"
rsync -a "$HERMES_HOME/cron/" "$BACKUP_CT:$BACKUP_DIR/cron/" 2>/dev/null && echo "  [OK] cron/"
rsync -a "$HERMES_HOME/mnemosyne/" "$BACKUP_CT:$BACKUP_DIR/mnemosyne/" 2>/dev/null && echo "  [OK] mnemosyne/"
echo ""

# ===== 2. Backup Hermes Source =====
echo "[2/5] Backing up Hermes source code..."
rsync -a --delete \
  --exclude='.git' --exclude='node_modules' --exclude='venv' --exclude='.venv' \
  --exclude='__pycache__' --exclude='*.pyc' \
  "$HERMES_SRC/" "$BACKUP_CT:$BACKUP_DIR/hermes-src/" 2>/dev/null && echo "  [OK] hermes source"
echo ""

# ===== 3. Full local archive =====
echo "[3/5] Creating local archive..."
FILES=()
for f in config.yaml .env state.db auth.json; do
    [ -f "$HERMES_HOME/$f" ] && FILES+=("$HERMES_HOME/$f")
done
[ -d "$HERMES_HOME/skills" ] && FILES+=("$HERMES_HOME/skills")

if [ ${#FILES[@]} -gt 0 ]; then
    tar -czf "/root/$FILENAME" "${FILES[@]}" 2>/dev/null && \
    echo "  [OK] /root/$FILENAME ($(du -h /root/$FILENAME | cut -f1))"
fi
echo ""

# ===== 4. Clean old archives =====
echo "[4/5] Cleaning old archives..."
ls -1t /root/hermes-backup-*.tar.gz 2>/dev/null | \
    tail -n +$((MAX_LOCAL+1)) | xargs rm -f 2>/dev/null
echo "  [OK] Keeping last $MAX_LOCAL archives"
echo ""

# ===== 5. Verify =====
echo "[5/5] Verifying backup..."
CT_SIZE=$(ssh -n "$BACKUP_CT" "du -sh $BACKUP_DIR 2>/dev/null | cut -f1")
CT_FILES=$(ssh -n "$BACKUP_CT" "find $BACKUP_DIR -type f 2>/dev/null | wc -l")
echo "  [OK] Target size: $CT_SIZE | Files: $CT_FILES"
echo ""

# ===== Summary =====
END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
echo "======= BACKUP COMPLETE ======="
echo "Status: ✅ Success"
echo "Duration: ${DURATION}s"
echo "Folder: $BACKUP_FOLDER -> $BACKUP_IP:$BACKUP_DIR"
echo "Local:  /root/$FILENAME"
