#!/bin/bash
# Hermes Agent Restore — Universal
# Restore Hermes backup from backup device to any server.
#
# Flow:
#   1. Pick which backup to restore
#   2. Enter the target Hermes server IP
#   3. Confirm -> automatically transfer all files from backup device to target
#
# Usage: bash hermes-restore.sh

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ===== CONFIG — set your backup device IP here =====
BACKUP_DEVICE_IP="YOUR_BACKUP_DEVICE_IP"   # <-- CHANGE THIS
BACKUP_CT="root@$BACKUP_DEVICE_IP"

clear 2>/dev/null || true
echo "================================================"
echo "     HERMES RESTORE — From Backup Device"
echo "================================================"
echo ""
echo "How it works:"
echo "  1. Pick a backup folder to restore"
echo "  2. Enter the target Hermes server IP"
echo "  3. Type RESTORE to confirm — files are sent automatically"
echo ""

# ===== Step 1: List available backups =====
echo "------------------------------------------"
echo "  STEP 1: Select Backup"
echo "------------------------------------------"
echo ""

BACKUP_LIST=$(ssh -n "$BACKUP_CT" '
if [ -d /root/backups ]; then
  for d in /root/backups/*/; do
    [ -d "$d" ] && echo "$(basename "$d")|$(du -sh "$d" | cut -f1)|$d"
  done
fi' 2>/dev/null)

if [ -z "$BACKUP_LIST" ]; then
    echo "No backups found on $BACKUP_CT!"
    echo ""
    echo "Check that:"
    echo "  - Backup device IP is correct ($BACKUP_DEVICE_IP)"
    echo "  - SSH key is registered"
    echo "  - A backup exists in /root/backups/*/"
    exit 1
fi

echo "Backups available on $BACKUP_CT:"
echo ""

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
    echo "  $INDEX) $NAME  ($SIZE)"
    INDEX=$((INDEX + 1))
done

echo ""
read -r -p "Enter backup number: " CHOICE
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -ge "${#DIRS[@]}" ]; then
    echo "Invalid number!"
    exit 1
fi

BACKUP_DIR="${DIRS[$CHOICE]}"
BACKUP_NAME="${NAMES[$CHOICE]}"

echo ""
echo "------------------------------------------"
echo "  STEP 2: Target Server"
echo "------------------------------------------"
echo ""
echo "Selected backup: $BACKUP_NAME ($(ssh -n "$BACKUP_CT" "du -sh $BACKUP_DIR 2>/dev/null | cut -f1"))"
echo ""

read -r -p "Target Hermes server IP (e.g. 192.168.1.100): " TARGET_IP

if [ -z "$TARGET_IP" ]; then
    echo "IP address is required!"
    exit 1
fi

TARGET_USER="root"
TARGET_HOME="/root/.hermes"
TARGET_SRC="/usr/local/lib/hermes-agent"

echo ""
echo "================================================"
echo "  RESTORE SUMMARY"
echo "================================================"
echo "  Backup:    $BACKUP_NAME"
echo "  From:      $BACKUP_CT"
echo "  To:        $TARGET_IP"
echo "  Contents:  config, skills, sessions, cron,"
echo "             mnemosyne, hermes source code"
echo "================================================"
echo ""
echo "WARNING: All Hermes files on $TARGET_IP will be overwritten!"
echo "  Old files will be backed up to: $TARGET_HOME.bak.<timestamp>"
echo ""

# ===== Step 3: Confirmation =====
echo "------------------------------------------"
echo "  STEP 3: Confirm"
echo "------------------------------------------"
echo ""
read -r -p "Type 'RESTORE' to proceed: " CONFIRM
if [ "$CONFIRM" != "RESTORE" ]; then
    echo "Restore cancelled."
    exit 1
fi

# ===== Backup old files on target =====
echo ""
echo "------------------------------------------"
echo "  BACKING UP OLD FILES"
echo "------------------------------------------"
echo ""
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ssh "$TARGET_USER@$TARGET_IP" "mkdir -p $TARGET_HOME.bak.$TIMESTAMP" 2>/dev/null
ssh "$TARGET_USER@$TARGET_IP" "cp $TARGET_HOME/config.yaml $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/.env $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/auth.json $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/state.db $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/skills $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/cron $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/mnemosyne $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null" 2>/dev/null
echo "  [OK] Old files saved to $TARGET_IP:$TARGET_HOME.bak.$TIMESTAMP"

# ===== Stop Hermes on target =====
echo ""
echo "------------------------------------------"
echo "  STOPPING HERMES ON TARGET"
echo "------------------------------------------"
echo ""
ssh "$TARGET_USER@$TARGET_IP" "pkill -f 'hermes.*gateway' 2>/dev/null || true; sleep 1" 2>/dev/null
echo "  [OK] Hermes gateway stopped"

# ===== Transfer files =====
echo ""
echo "------------------------------------------"
echo "  TRANSFERRING FILES TO $TARGET_IP"
echo "------------------------------------------"
echo ""
rsync -a "$BACKUP_CT:$BACKUP_DIR/config/config.yaml" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] config.yaml" || echo "  [SKIP] config.yaml"
rsync -a "$BACKUP_CT:$BACKUP_DIR/config/.env" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] .env" || echo "  [SKIP] .env"
rsync -a "$BACKUP_CT:$BACKUP_DIR/config/auth.json" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] auth.json" || echo "  [SKIP] auth.json"
rsync -a "$BACKUP_CT:$BACKUP_DIR/sessions/state.db" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] state.db" || echo "  [SKIP] state.db"
rsync -a --delete "$BACKUP_CT:$BACKUP_DIR/skills/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/skills/" 2>/dev/null && echo "  [OK] skills/" || echo "  [SKIP] skills/"
rsync -a --delete "$BACKUP_CT:$BACKUP_DIR/cron/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/cron/" 2>/dev/null && echo "  [OK] cron/" || echo "  [SKIP] cron/"
rsync -a --delete "$BACKUP_CT:$BACKUP_DIR/mnemosyne/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/mnemosyne/" 2>/dev/null && echo "  [OK] mnemosyne/" || echo "  [SKIP] mnemosyne/"

# ===== Restore source code =====
echo ""
echo "------------------------------------------"
echo "  RESTORING SOURCE CODE"
echo "------------------------------------------"
echo ""
if ssh -n "$BACKUP_CT" "test -d $BACKUP_DIR/hermes-src" 2>/dev/null; then
    rsync -a --delete \
      --exclude='.git' --exclude='node_modules' --exclude='venv' --exclude='.venv' \
      --exclude='__pycache__' --exclude='*.pyc' \
      "$BACKUP_CT:$BACKUP_DIR/hermes-src/" "$TARGET_USER@$TARGET_IP:$TARGET_SRC/" 2>/dev/null && echo "  [OK] hermes source code"
else
    echo "  [SKIP] hermes source (not in this backup)"
fi

# ===== Fix permissions =====
echo ""
echo "------------------------------------------"
echo "  FIXING PERMISSIONS"
echo "------------------------------------------"
echo ""
ssh "$TARGET_USER@$TARGET_IP" "chmod 600 $TARGET_HOME/.env $TARGET_HOME/auth.json $TARGET_HOME/state.db 2>/dev/null" 2>/dev/null
echo "  [OK] Permissions set"

# ===== Start Hermes =====
echo ""
echo "------------------------------------------"
echo "  STARTING HERMES"
echo "------------------------------------------"
echo ""
ssh "$TARGET_USER@$TARGET_IP" "cd $TARGET_SRC 2>/dev/null; nohup hermes gateway start > /dev/null 2>&1 &" 2>/dev/null
sleep 2
echo "  [OK] Hermes gateway started on $TARGET_IP"

echo ""
echo "================================================"
echo "  RESTORE COMPLETE!"
echo "================================================"
echo ""
echo "  Backup:  $BACKUP_NAME"
echo "  From:    $BACKUP_CT"
echo "  To:      $TARGET_IP"
echo ""
echo "  Old files saved at: $TARGET_HOME.bak.$TIMESTAMP"
echo ""
echo "  To rollback manually:"
echo "  ssh $TARGET_USER@$TARGET_IP 'cp $TARGET_HOME.bak.$TIMESTAMP/config.yaml $TARGET_HOME/'"
echo "  ssh $TARGET_USER@$TARGET_IP 'cp $TARGET_HOME.bak.$TIMESTAMP/.env $TARGET_HOME/'"
echo "  (and restart Hermes)"
echo ""
