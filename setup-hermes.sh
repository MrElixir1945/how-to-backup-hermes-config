#!/bin/bash
# Setup Hermes — Restore + Auto Backup + Config
# Satu skrip buat balikin data + nyetel backup harian.
#
# Cara pake:
#   bash setup-hermes.sh                              # interaktif
#   bash setup-hermes.sh <BACKUP_DEVICE_IP>            # langsung pake IP
#
# Nanti bakal:
#   1. Restore data dari backup device
#   2. Setup cron backup otomatis tiap 3 pagi
#   3. Simpan konfigurasi backup-target.conf

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "================================================"
echo "     SETUP HERMES — Restore + Auto Backup"
echo "================================================"
echo ""

# ===== Cek argument / minta IP backup device =====
if [ -n "$1" ]; then
    BACKUP_DEVICE_IP="$1"
else
    read -r -p "IP backup device (tempat nyimpen backup): " BACKUP_DEVICE_IP
fi

if [ -z "$BACKUP_DEVICE_IP" ]; then
    echo "❌ IP backup device wajib diisi!"
    exit 1
fi

# Test koneksi dulu
echo ""
echo "⏳ Tes koneksi ke backup device..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$BACKUP_DEVICE_IP" "echo OK" 2>/dev/null; then
    echo "❌ Gak bisa connect ke root@$BACKUP_DEVICE_IP"
    echo ""
    echo "Pastikan:"
    echo "  - SSH key sudah terdaftar (ssh-copy-id root@$BACKUP_DEVICE_IP)"
    echo "  - IP-nya bener"
    echo "  - Backup device nyala"
    exit 1
fi
echo "✅ Koneksi OK!"
echo ""

# ===== Step 1: Backup config file =====
echo "------------------------------------------"
echo "  LANGKAH 1: Setup Config"
echo "------------------------------------------"
echo ""

# Bikin folder scripts kalo belum ada
mkdir -p ~/.hermes/scripts

# Simpan konfigurasi backup
read -r -p "Nama folder backup (enter aja kalo mau pake hostname): " FOLDER_NAME
if [ -z "$FOLDER_NAME" ]; then
    FOLDER_NAME="$(hostname -s)"
fi

cat > ~/.hermes/scripts/backup-target.conf << EOF
BACKUP_IP=$BACKUP_DEVICE_IP
BACKUP_USER=root
BACKUP_FOLDER=$FOLDER_NAME
EOF
echo "✅ Config disimpan di ~/.hermes/scripts/backup-target.conf"

# Download backup script juga
if [ ! -f ~/.hermes/scripts/hermes-backup.sh ]; then
    echo "⏳ Download hermes-backup.sh..."
    curl -s -o ~/.hermes/scripts/hermes-backup.sh \
        https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/hermes-backup.sh
    chmod +x ~/.hermes/scripts/hermes-backup.sh
    echo "✅ hermes-backup.sh siap"
fi

echo ""

# ===== Step 2: Cek backup yang tersedia =====
echo "------------------------------------------"
echo "  LANGKAH 2: Restore Data"
echo "------------------------------------------"
echo ""

# Cek apa ada backup
BACKUP_LIST=$(ssh -n "root@$BACKUP_DEVICE_IP" 'if [ -d /root/backups ]; then for d in /root/backups/*/; do [ -d "$d" ] && echo "$(basename "$d")|$(du -sh "$d" | cut -f1)"; done; fi' 2>/dev/null)

if [ -z "$BACKUP_LIST" ]; then
    echo "ℹ️  Gak ada backup di $BACKUP_DEVICE_IP — lewatin restore."
    echo "   Nanti backup pertama jalan otomatis malam ini."
    echo ""
    read -r -p "Langsung setup cron backup aja? (y/n): " SKIP_RESTORE
    if [[ "$SKIP_RESTORE" =~ ^[Yy]$ ]]; then
        # Langsung ke cron setup
        :
    else
        echo "Ok, keluar."
        exit 0
    fi
else
    # Ada backup, tanya mau restore atau skip
    echo "Backup tersedia:"
    echo ""

    IFS=$'\n'
    ITEMS=($BACKUP_LIST)
    unset IFS

    for i in "${!ITEMS[@]}"; do
        echo "  $i) $(echo "${ITEMS[$i]}" | cut -d'|' -f1)  ($(echo "${ITEMS[$i]}" | cut -d'|' -f2))"
    done

    echo ""
    read -r -p "Mau restore backup? (y/n): " DO_RESTORE

    if [[ "$DO_RESTORE" =~ ^[Yy]$ ]]; then
        # Download restore script
        echo "⏳ Download hermes-restore.sh..."
        curl -s -o /tmp/hermes-restore.sh \
            https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/hermes-restore.sh

        # Ganti IP backup device
        sed -i "s/YOUR_BACKUP_DEVICE_IP/$BACKUP_DEVICE_IP/g" /tmp/hermes-restore.sh
        chmod +x /tmp/hermes-restore.sh

        echo "✅ Siap! Jalanin restore..."
        echo ""
        bash /tmp/hermes-restore.sh

        rm -f /tmp/hermes-restore.sh
    else
        echo "ℹ️  Restore dilewatin."
    fi
fi

echo ""

# ===== Step 3: Setup cron backup =====
echo "------------------------------------------"
echo "  LANGKAH 3: Setup Cron Backup"
echo "------------------------------------------"
echo ""

# Cek apa udah ada cron
EXISTING_CRON=$(hermes cron list 2>/dev/null | grep -i "hermes-backup")

if [ -n "$EXISTING_CRON" ]; then
    echo "ℹ️  Cron backup udah ada:"
    echo "   $EXISTING_CRON"
    echo ""
else
    read -r -p "Jam berapa backup otomatis? (default: 3, berarti 03:00): " BACKUP_HOUR
    BACKUP_HOUR="${BACKUP_HOUR:-3}"

    # Validasi angka
    if ! [[ "$BACKUP_HOUR" =~ ^[0-9]+$ ]] || [ "$BACKUP_HOUR" -lt 0 ] || [ "$BACKUP_HOUR" -gt 23 ]; then
        echo "⚠️  Jam gak valid, pake default 3."
        BACKUP_HOUR=3
    fi

    echo "⏳ Setup cron backup jam ${BACKUP_HOUR}:00..."
    hermes cron create \
        --name "hermes-backup" \
        --schedule "0 $BACKUP_HOUR * * *" \
        --script hermes-backup.sh \
        --no-agent 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "✅ Cron backup sukses!"
    else
        echo "⚠️  Gagal pake hermes cron, coba cara manual..."
        # Fallback: bikin cron langsung
        (crontab -l 2>/dev/null | grep -v "hermes-backup"; echo "0 $BACKUP_HOUR * * * cd ~/.hermes/scripts && bash hermes-backup.sh") | crontab -
        echo "✅ Cron manual di /etc/crontab / crontab user"
    fi
fi

echo ""

# ===== Selesai =====
echo "================================================"
echo "  ✅ SETUP SELESAI!"
echo "================================================"
echo ""
echo "  Backup device:  $BACKUP_DEVICE_IP"
echo "  Folder backup:  $FOLDER_NAME"
echo ""
echo "  File config:    ~/.hermes/scripts/backup-target.conf"
echo "  Backup script:  ~/.hermes/scripts/hermes-backup.sh"
echo ""
echo "  Backup otomatis tiap jam ${BACKUP_HOUR}:00"
echo ""

# Jalanin backup pertama sekarang?
read -r -p "Jalanin backup sekarang juga? (y/n): " RUN_NOW
if [[ "$RUN_NOW" =~ ^[Yy]$ ]]; then
    echo ""
    echo "⏳ Backup pertama..."
    bash ~/.hermes/scripts/hermes-backup.sh
    echo ""
    echo "✅ Selesai!"
fi

echo ""
echo "Enjoy Bos 🚀"
