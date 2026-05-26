#!/bin/bash
# Hermes Agent Restore — Universal
# Restore Hermes backup from backup device to any server.
#
# Usage: bash hermes-restore.sh
# You'll be prompted to choose a backup and enter the target IP.

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
BACKUP_CT="root@10.10.10.116"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

clear 2>/dev/null || true
echo "================================================"
echo "     HERMES RESTORE — From Backup Device"
echo "================================================"
echo ""

# Scan available backups
echo "[1] Scanning backups on $BACKUP_CT..."
echo ""

BACKUP_LIST=$(ssh -n root@10.10.10.116 '
if [ -d /root/backups ]; then
  for d in /root/backups/*/; do
    [ -d "$d" ] && echo "$(basename "$d")|$(du -sh "$d" | cut -f1)|$d"
  done
fi' 2>/dev/null)

if [ -z "$BACKUP_LIST" ]; then
    echo "❌ No backups found on $BACKUP_CT!"
    exit 1
fi

IFS=$'\n'
BACKUP_ITEMS=($BACKUP_LIST)
unset IFS

INDEX=0
NAMES=()
DIRS=()
for item in "${BACKUP_ITEMS[@]}"; do
    NAME=$(echo "$item" | cut -d'|' -f1)
    SIZE=$(echo "$item" | cut -d'|' -f2)
    DIR=$(echo "$item" | cut -d'|' -f3)
    NAMES+=("$NAME")
    DIRS+=("$DIR")
    echo "   $INDEX) $NAME  ($SIZE)"
    INDEX=$((INDEX + 1))
done

echo ""
read -r -p "Select backup number: " CHOICE
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -ge "${#DIRS[@]}" ]; then
    echo "❌ Invalid choice!"
    exit 1
fi

BACKUP_DIR="${DIRS[$CHOICE]}"
BACKUP_NAME="${NAMES[$CHOICE]}"

echo ""
read -r -p "Target Hermes server IP (e.g. 10.10.10.117): " TARGET_IP

if [ -z "$TARGET_IP" ]; then
    echo "❌ IP is required!"
    exit 1
fi

TARGET_USER="root"
TARGET_HOME="/root/.hermes"
TARGET_SRC="/usr/local/lib/hermes-agent"

echo ""
echo "================================================"
echo "  RESTORE: $BACKUP_NAME"
echo "  From:    $BACKUP_CT"
echo "  To:      $TARGET_IP"
echo "================================================"
echo ""
echo "⚠️  WARNING: This will OVERWRITE all Hermes files on $TARGET_IP!"
echo ""
read -r -p "Type 'RESTORE' to continue: " CONFIRM
if [ "$CONFIRM" != "RESTORE" ]; then
    echo "❌ Restore cancelled."
    exit 1
fi

# Backup existing files on target
echo ""
echo "=== Step 1: Backup existing files on target ==="
ssh "$TARGET_USER@$TARGET_IP" "mkdir -p $TARGET_HOME.bak.$TIMESTAMP" 2>/dev/null
ssh "$TARGET_USER@$TARGET_IP" "cp $TARGET_HOME/config.yaml $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/.env $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/auth.json $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/state.db $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/skills $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/cron $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/mnemosyne $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null" 2>/dev/null
echo "  [OK] Backed up -> $TARGET_IP:$TARGET_HOME.bak.$TIMESTAMP"

# Stop Hermes on target
echo ""
echo "=== Step 2: Stop Hermes on target ==="
ssh "$TARGET_USER@$TARGET_IP" "pkill -f 'hermes.*gateway' 2>/dev/null || true; sleep 1" 2>/dev/null
echo "  [OK] Gateway stopped"

# Push backup to target
echo ""
echo "=== Step 3: Push backup to $TARGET_IP ==="
rsync -a "$BACKUP_CT:$BACKUP_DIR/config/config.yaml" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] config.yaml" || echo "  [SKIP] config.yaml"
rsync -a "$BACKUP_CT:$BACKUP_DIR/config/.env" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] .env" || echo "  [SKIP] .env"
rsync -a "$BACKUP_CT:$BACKUP_DIR/config/auth.json" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] auth.json" || echo "  [SKIP] auth.json"
rsync -a "$BACKUP_CT:$BACKUP_DIR/sessions/state.db" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] state.db" || echo "  [SKIP] state.db"
rsync -a --delete "$BACKUP_CT:$BACKUP_DIR/skills/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/skills/" 2>/dev/null && echo "  [OK] skills/" || echo "  [SKIP] skills/"
rsync -a --delete "$BACKUP_CT:$BACKUP_DIR/cron/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/cron/" 2>/dev/null && echo "  [OK] cron/" || echo "  [SKIP] cron/"
rsync -a --delete "$BACKUP_CT:$BACKUP_DIR/mnemosyne/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/mnemosyne/" 2>/dev/null && echo "  [OK] mnemosyne/" || echo "  [SKIP] mnemosyne/"

# Restore Hermes source
echo ""
echo "=== Step 4: Restore Hermes source code ==="
if ssh -n root@10.10.10.116 "test -d $BACKUP_DIR/hermes-src" 2>/dev/null; then
    rsync -a --delete \
      --exclude='.git' --exclude='node_modules' --exclude='venv' --exclude='.venv' \
      --exclude='__pycache__' --exclude='*.pyc' \
      "$BACKUP_CT:$BACKUP_DIR/hermes-src/" "$TARGET_USER@$TARGET_IP:$TARGET_SRC/" 2>/dev/null && echo "  [OK] hermes source"
else
    echo "  [SKIP] hermes source (not in this backup)"
fi

# Fix permissions
echo ""
echo "=== Step 5: Fix permissions ==="
ssh "$TARGET_USER@$TARGET_IP" "chmod 600 $TARGET_HOME/.env $TARGET_HOME/auth.json $TARGET_HOME/state.db 2>/dev/null" 2>/dev/null
echo "  [OK] permissions"

# Restart Hermes
echo ""
echo "=== Step 6: Restart Hermes ==="
ssh "$TARGET_USER@$TARGET_IP" "cd $TARGET_SRC 2>/dev/null; nohup hermes gateway start > /dev/null 2>&1 &" 2>/dev/null
echo "  [OK] Hermes restarted on $TARGET_IP"

echo ""
echo "================================================"
echo "  ✅ RESTORE COMPLETE!"
echo "================================================"
echo "  Backup:  $BACKUP_NAME"
echo "  From:    $BACKUP_CT"
echo "  To:      $TARGET_IP"
echo "  Old files: $TARGET_HOME.bak.$TIMESTAMP"
echo ""
echo "To rollback:"
echo "  ssh $TARGET_USER@$TARGET_IP 'cp $TARGET_HOME.bak.$TIMESTAMP/config.yaml $TARGET_HOME/'"
echo "  ssh $TARGET_USER@$TARGET_IP 'cp $TARGET_HOME.bak.$TIMESTAMP/.env $TARGET_HOME/'"
echo ""
