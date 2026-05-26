#!/bin/bash
# Setup Hermes — Restore + Auto Backup + Config
# One script to restore data, configure backups, and set up cron.
#
# Usage:
#   bash setup-hermes.sh                          # interactive
#   bash setup-hermes.sh <BACKUP_DEVICE_IP>        # pass IP directly
#
# What it does:
#   1. Configure backup destination (which server to save backups to)
#   2. Optionally restore from an existing backup
#   3. Schedule automatic daily backup via cron

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "================================================"
echo "     SETUP HERMES — Restore + Auto Backup"
echo "================================================"
echo ""

# ===== Get backup storage device IP =====
# This is the IP of the server/CT that stores all the backups.
# Example: If your backup device is at 192.168.1.100, enter that.
if [ -n "$1" ]; then
    BACKUP_DEVICE_IP="$1"
else
    echo "Enter the IP of the device where backups are stored."
    echo "This is the server/CT that receives and holds backup files."
    echo ""
    read -r -p "Backup storage device IP: " BACKUP_DEVICE_IP
fi

if [ -z "$BACKUP_DEVICE_IP" ]; then
    echo "ERROR: Backup device IP is required."
    exit 1
fi

# Test connection
echo ""
echo "Testing connection to $BACKUP_DEVICE_IP..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$BACKUP_DEVICE_IP" "echo OK" 2>/dev/null; then
    echo "ERROR: Cannot connect to root@$BACKUP_DEVICE_IP"
    echo ""
    echo "Make sure:"
    echo "  - SSH key is set up (ssh-copy-id root@$BACKUP_DEVICE_IP)"
    echo "  - The IP is correct"
    echo "  - The backup device is running"
    exit 1
fi
echo "OK - Connected to backup storage device."
echo ""

# ===== Step 1: Save config =====
echo "------------------------------------------"
echo "  STEP 1: Configuration"
echo "------------------------------------------"
echo ""

mkdir -p ~/.hermes/scripts

read -r -p "Name for this server in backups (press Enter to use hostname): " FOLDER_NAME
if [ -z "$FOLDER_NAME" ]; then
    FOLDER_NAME="$(hostname -s)"
fi

cat > ~/.hermes/scripts/backup-target.conf << EOF
BACKUP_IP=$BACKUP_DEVICE_IP
BACKUP_USER=root
BACKUP_FOLDER=$FOLDER_NAME
EOF
echo "Saved config to ~/.hermes/scripts/backup-target.conf"

# Download backup script if not present
if [ ! -f ~/.hermes/scripts/hermes-backup.sh ]; then
    echo "Downloading hermes-backup.sh..."
    curl -s -o ~/.hermes/scripts/hermes-backup.sh \
        https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/hermes-backup.sh
    chmod +x ~/.hermes/scripts/hermes-backup.sh
    echo "OK - hermes-backup.sh ready"
fi

echo ""

# ===== Step 2: Check for existing backups =====
echo "------------------------------------------"
echo "  STEP 2: Restore Data (optional)"
echo "------------------------------------------"
echo ""

BACKUP_LIST=$(ssh -n "root@$BACKUP_DEVICE_IP" 'if [ -d /root/backups ]; then for d in /root/backups/*/; do [ -d "$d" ] && echo "$(basename "$d")|$(du -sh "$d" | cut -f1)"; done; fi' 2>/dev/null)

if [ -z "$BACKUP_LIST" ]; then
    echo "No existing backups found on $BACKUP_DEVICE_IP."
    echo "Skipping restore. First backup will run later."
    echo ""
else
    echo "The following backups exist on the storage device:"
    echo ""

    IFS=$'\n'
    ITEMS=($BACKUP_LIST)
    unset IFS

    for i in "${!ITEMS[@]}"; do
        echo "  $i) $(echo "${ITEMS[$i]}" | cut -d'|' -f1)  ($(echo "${ITEMS[$i]}" | cut -d'|' -f2))"
    done

    echo ""
    echo "  n) None — skip restore, just set up backups"
    echo ""

    read -r -p "Enter number to restore, or n to skip: " RESTORE_CHOICE

    if [[ "$RESTORE_CHOICE" =~ ^[0-9]+$ ]] && [ "$RESTORE_CHOICE" -lt "${#ITEMS[@]}" ]; then
        echo ""
        echo "Downloading restore script..."
        curl -s -o /tmp/hermes-restore.sh \
            https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/hermes-restore.sh

        sed -i "s/YOUR_BACKUP_DEVICE_IP/$BACKUP_DEVICE_IP/g" /tmp/hermes-restore.sh
        chmod +x /tmp/hermes-restore.sh

        echo "Ready! Running restore..."
        echo ""
        bash /tmp/hermes-restore.sh

        rm -f /tmp/hermes-restore.sh
    else
        echo "Restore skipped."
    fi
fi

echo ""

# ===== Step 3: Setup cron =====
echo "------------------------------------------"
echo "  STEP 3: Schedule Automatic Backup"
echo "------------------------------------------"
echo ""

EXISTING_CRON=$(hermes cron list 2>/dev/null | grep -i "hermes-backup")

if [ -n "$EXISTING_CRON" ]; then
    echo "A backup cron job already exists:"
    echo "   $EXISTING_CRON"
    echo ""
else
    read -r -p "Hour for daily backup? (0-23, default 3 = 03:00): " BACKUP_HOUR
    BACKUP_HOUR="${BACKUP_HOUR:-3}"

    if ! [[ "$BACKUP_HOUR" =~ ^[0-9]+$ ]] || [ "$BACKUP_HOUR" -lt 0 ] || [ "$BACKUP_HOUR" -gt 23 ]; then
        echo "Invalid hour. Using default (3)."
        BACKUP_HOUR=3
    fi

    echo "Setting up cron for ${BACKUP_HOUR}:00 daily..."
    hermes cron create \
        --name "hermes-backup" \
        --schedule "0 $BACKUP_HOUR * * *" \
        --script hermes-backup.sh \
        --no-agent 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "OK - Cron backup created successfully!"
    else
        echo "hermes cron failed, falling back to system crontab..."
        (crontab -l 2>/dev/null | grep -v "hermes-backup"; echo "0 $BACKUP_HOUR * * * cd ~/.hermes/scripts && bash hermes-backup.sh") | crontab -
        echo "OK - System crontab updated"
    fi
fi

echo ""

# ===== Done =====
echo "================================================"
echo "  SETUP COMPLETE!"
echo "================================================"
echo ""
echo "  Backup storage device:  $BACKUP_DEVICE_IP"
echo "  This server's backup folder:  $FOLDER_NAME"
echo ""
echo "  Config file:    ~/.hermes/scripts/backup-target.conf"
echo "  Backup script:  ~/.hermes/scripts/hermes-backup.sh"
echo ""
echo "  Scheduled at:   ${BACKUP_HOUR}:00 daily"
echo ""

read -r -p "Run the first backup now? (y/n): " RUN_NOW
if [[ "$RUN_NOW" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Running first backup..."
    bash ~/.hermes/scripts/hermes-backup.sh
fi

echo ""
echo "Done."
