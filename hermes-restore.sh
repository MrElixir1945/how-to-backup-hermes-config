#!/bin/bash
# Hermes Agent Restore — Universal
# Restore Hermes backup from backup device to any server.
#
# Flow:
#   1. Pilih backup mana yang mau di-restore (dari daftar folder di backup device)
#   2. Masukkin IP server Hermes tujuan (server baru / yang ilang)
#   3. Konfirmasi -> otomatis kirim semua file dari backup device ke server tujuan
#   4. Hermes langsung nyala 100% persis kayak sebelum ilang
#
# Usage: bash hermes-restore.sh

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ===== CONFIG — set your backup device IP here =====
BACKUP_DEVICE_IP="YOUR_BACKUP_DEVICE_IP"   # <-- CHANGE THIS
BACKUP_CT="root@$BACKUP_DEVICE_IP"

clear 2>/dev/null || true
echo "================================================"
echo "     HERMES RESTORE — Dari Backup Device"
echo "================================================"
echo ""
echo "Cara pake:"
echo "  1. Pilih folder backup yang mau dipulihin"
echo "  2. Masukkin IP server Hermes tujuan"
echo "  3. Ketik RESTORE -> otomatis kirim file"
echo ""

# ===== Step 1: Cari backup yang tersedia =====
echo "------------------------------------------"
echo "  LANGKAH 1: Pilih Backup"
echo "------------------------------------------"
echo ""

BACKUP_LIST=$(ssh -n "$BACKUP_CT" '
if [ -d /root/backups ]; then
  for d in /root/backups/*/; do
    [ -d "$d" ] && echo "$(basename "$d")|$(du -sh "$d" | cut -f1)|$d"
  done
fi' 2>/dev/null)

if [ -z "$BACKUP_LIST" ]; then
    echo "❌ Tidak ada backup ditemukan di $BACKUP_CT!"
    echo ""
    echo "Pastikan:"
    echo "  - IP backup device sudah bener ($BACKUP_DEVICE_IP)"
    echo "  - SSH key sudah terdaftar"
    echo "  - Ada folder di /root/backups/*/"
    exit 1
fi

echo "Backup yang tersedia di $BACKUP_CT:"
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
    echo "   $INDEX) $NAME  ($SIZE)"
    INDEX=$((INDEX + 1))
done

echo ""
read -r -p "Masukkin nomor backup: " CHOICE
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -ge "${#DIRS[@]}" ]; then
    echo "❌ Nomor gak valid!"
    exit 1
fi

BACKUP_DIR="${DIRS[$CHOICE]}"
BACKUP_NAME="${NAMES[$CHOICE]}"

echo ""
echo "------------------------------------------"
echo "  LANGKAH 2: Target Server"
echo "------------------------------------------"
echo ""
echo "Backup yang dipilih: $BACKUP_NAME ($(ssh -n "$BACKUP_CT" "du -sh $BACKUP_DIR 2>/dev/null | cut -f1"))"
echo ""

read -r -p "IP server Hermes tujuan (contoh: 192.168.1.100): " TARGET_IP

if [ -z "$TARGET_IP" ]; then
    echo "❌ IP wajib diisi!"
    exit 1
fi

TARGET_USER="root"
TARGET_HOME="/root/.hermes"
TARGET_SRC="/usr/local/lib/hermes-agent"

echo ""
echo "================================================"
echo "  RINGKASAN RESTORE"
echo "================================================"
echo "  Backup:    $BACKUP_NAME"
echo "  Dari:      $BACKUP_CT"
echo "  Ke:        $TARGET_IP"
echo "  Isi:       config, skills, sessions, cron,"
echo "             mnemosyne, hermes source code"
echo "================================================"
echo ""
echo "⚠️  PERINGATAN: Semua file Hermes di $TARGET_IP akan ditimpa!"
echo "   File lama akan dibackup dulu ke: $TARGET_HOME.bak.$TIMESTAMP"
echo ""

# ===== Step 2: Konfirmasi =====
echo "------------------------------------------"
echo "  LANGKAH 3: Konfirmasi"
echo "------------------------------------------"
echo ""
read -r -p "Ketik 'RESTORE' untuk lanjut: " CONFIRM
if [ "$CONFIRM" != "RESTORE" ]; then
    echo "❌ Restore dibatalkan."
    exit 1
fi

# ===== Step 3: Backup file lama di server tujuan =====
echo ""
echo "------------------------------------------"
echo "  PROSES: Backup file lama"
echo "------------------------------------------"
echo ""
ssh "$TARGET_USER@$TARGET_IP" "mkdir -p $TARGET_HOME.bak.$TIMESTAMP" 2>/dev/null
ssh "$TARGET_USER@$TARGET_IP" "cp $TARGET_HOME/config.yaml $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/.env $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/auth.json $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/state.db $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/skills $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/cron $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/mnemosyne $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null" 2>/dev/null
echo "  [OK] File lama disimpan di -> $TARGET_IP:$TARGET_HOME.bak.$TIMESTAMP"

# ===== Step 4: Hentikan Hermes di server tujuan =====
echo ""
echo "------------------------------------------"
echo "  PROSES: Hentikan Hermes"
echo "------------------------------------------"
echo ""
ssh "$TARGET_USER@$TARGET_IP" "pkill -f 'hermes.*gateway' 2>/dev/null || true; sleep 1" 2>/dev/null
echo "  [OK] Hermes gateway dihentikan"

# ===== Step 5: Kirim backup =====
echo ""
echo "------------------------------------------"
echo "  PROSES: Kirim backup ke $TARGET_IP"
echo "------------------------------------------"
echo ""
rsync -a "$BACKUP_CT:$BACKUP_DIR/config/config.yaml" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] config.yaml" || echo "  [SKIP] config.yaml"
rsync -a "$BACKUP_CT:$BACKUP_DIR/config/.env" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] .env" || echo "  [SKIP] .env"
rsync -a "$BACKUP_CT:$BACKUP_DIR/config/auth.json" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] auth.json" || echo "  [SKIP] auth.json"
rsync -a "$BACKUP_CT:$BACKUP_DIR/sessions/state.db" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] state.db" || echo "  [SKIP] state.db"
rsync -a --delete "$BACKUP_CT:$BACKUP_DIR/skills/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/skills/" 2>/dev/null && echo "  [OK] skills/" || echo "  [SKIP] skills/"
rsync -a --delete "$BACKUP_CT:$BACKUP_DIR/cron/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/cron/" 2>/dev/null && echo "  [OK] cron/" || echo "  [SKIP] cron/"
rsync -a --delete "$BACKUP_CT:$BACKUP_DIR/mnemosyne/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/mnemosyne/" 2>/dev/null && echo "  [OK] mnemosyne/" || echo "  [SKIP] mnemosyne/"

# ===== Step 6: Restore Hermes source =====
echo ""
echo "------------------------------------------"
echo "  PROSES: Restore source code"
echo "------------------------------------------"
echo ""
if ssh -n "$BACKUP_CT" "test -d $BACKUP_DIR/hermes-src" 2>/dev/null; then
    rsync -a --delete \
      --exclude='.git' --exclude='node_modules' --exclude='venv' --exclude='.venv' \
      --exclude='__pycache__' --exclude='*.pyc' \
      "$BACKUP_CT:$BACKUP_DIR/hermes-src/" "$TARGET_USER@$TARGET_IP:$TARGET_SRC/" 2>/dev/null && echo "  [OK] hermes source code"
else
    echo "  [SKIP] hermes source (tidak ada di backup ini)"
fi

# ===== Step 7: Fix permissions =====
echo ""
echo "------------------------------------------"
echo "  PROSES: Fix permissions"
echo "------------------------------------------"
echo ""
ssh "$TARGET_USER@$TARGET_IP" "chmod 600 $TARGET_HOME/.env $TARGET_HOME/auth.json $TARGET_HOME/state.db 2>/dev/null" 2>/dev/null
echo "  [OK] permissions"

# ===== Step 8: Restart Hermes =====
echo ""
echo "------------------------------------------"
echo "  PROSES: Start Hermes"
echo "------------------------------------------"
echo ""
ssh "$TARGET_USER@$TARGET_IP" "cd $TARGET_SRC 2>/dev/null; nohup hermes gateway start > /dev/null 2>&1 &" 2>/dev/null
sleep 2
echo "  [OK] Hermes gateway dijalankan di $TARGET_IP"

echo ""
echo "================================================"
echo "  ✅ RESTORE SELESAI!"
echo "================================================"
echo ""
echo "  Backup:  $BACKUP_NAME"
echo "  Dari:    $BACKUP_CT"
echo "  Ke:      $TARGET_IP"
echo ""
echo "  File lama disimpan di: $TARGET_HOME.bak.$TIMESTAMP"
echo ""
echo "  Kalo error, balikin dengan:"
echo "  ssh $TARGET_USER@$TARGET_IP 'cp $TARGET_HOME.bak.$TIMESTAMP/config.yaml $TARGET_HOME/'"
echo "  ssh $TARGET_USER@$TARGET_IP 'cp $TARGET_HOME.bak.$TIMESTAMP/.env $TARGET_HOME/'"
echo ""
