#!/bin/bash
# Hermes Agent Auto-Backup
# Copy this script to ~/.hermes/scripts/hermes-backup.sh
# Then schedule it: hermes cron create --name hermes-backup --schedule "0 19 * * *" --script ~/.hermes/scripts/hermes-backup.sh --no-agent
#
# CONFIGURATION - Change these to match your setup:
HERMES_HOME="$HOME/.hermes"
GIT_REPO="/root/hermes-backup"
DATE=$(date +%Y-%m-%d)
FILENAME="hermes-backup-$DATE.tar.gz"
MAX_LOCAL=7  # Keep last 7 local archives

# ===== Step 1: Copy config to repo =====
mkdir -p "$GIT_REPO/config" "$GIT_REPO/skills" "$GIT_REPO/sessions"

cp "$HERMES_HOME/config.yaml" "$GIT_REPO/config/" 2>/dev/null
cp "$HERMES_HOME/state.db" "$GIT_REPO/sessions/" 2>/dev/null
cp "$HERMES_HOME/auth.json" "$GIT_REPO/config/" 2>/dev/null
cp -r "$HERMES_HOME/skills/"* "$GIT_REPO/skills/" 2>/dev/null

# ===== Step 2: Create a full local backup (includes .env) =====
FILES=()
for f in config.yaml .env state.db auth.json; do
    [ -f "$HERMES_HOME/$f" ] && FILES+=("$HERMES_HOME/$f")
done
[ -d "$HERMES_HOME/skills" ] && FILES+=("$HERMES_HOME/skills")

if [ ${#FILES[@]} -gt 0 ]; then
    tar -czf "/root/$FILENAME" "${FILES[@]}" 2>/dev/null && \
    echo "SAVED: /root/$FILENAME"
fi

# ===== Step 3: Clean old local archives =====
ls -1t /root/hermes-backup-*.tar.gz 2>/dev/null | \
    tail -n +$((MAX_LOCAL+1)) | xargs rm -f 2>/dev/null

# ===== Step 4: Push safe files to GitHub =====
cd "$GIT_REPO" || exit 1

if [ -n "$(git status --porcelain)" ]; then
    git add .
    git commit -m "backup $DATE"
    git push origin HEAD:main 2>&1 && echo "PUSHED: GitHub OK"
else
    echo "SKIPPED: no changes since last backup"
fi
