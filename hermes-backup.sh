#!/bin/bash
# Hermes Agent Auto-Backup
# Push safe files (config.yaml + skills/ + memories/) to GitHub.
# Full backup (with .env, auth, sessions) saved locally as .tar.gz
#
# CONFIGURATION:
HERMES_HOME="$HOME/.hermes"
GIT_REPO="/root/hermes-backup"
DATE=$(date +%Y-%m-%d)
MAX_LOCAL=7

# ===== SAFE FILES → GITHUB =====
# Only config.yaml, skills/, memories/ are pushed.
# auth.json, state.db, .env are NEVER pushed — they stay in local archive.
mkdir -p "$GIT_REPO/config" "$GIT_REPO/skills" "$GIT_REPO/memories"

cp "$HERMES_HOME/config.yaml" "$GIT_REPO/config/" 2>/dev/null
cp -r "$HERMES_HOME/skills/"* "$GIT_REPO/skills/" 2>/dev/null
cp -r "$HERMES_HOME/memories/"* "$GIT_REPO/memories/" 2>/dev/null

cd "$GIT_REPO" || exit 1
if [ -n "$(git status --porcelain)" ]; then
    git add .
    git commit -m "backup $DATE"
    git push origin HEAD:main 2>&1 && echo "GITHUB: pushed OK" || echo "GITHUB: push failed"
fi

# ===== FULL LOCAL BACKUP (with secrets) =====
# Stays on your server only — includes .env, auth.json, state.db
FILES=()
for f in config.yaml .env state.db auth.json; do
    [ -f "$HERMES_HOME/$f" ] && FILES+=("$HERMES_HOME/$f")
done
for d in skills memories; do
    [ -d "$HERMES_HOME/$d" ] && FILES+=("$HERMES_HOME/$d")
done

if [ ${#FILES[@]} -gt 0 ]; then
    tar -czf "/root/hermes-backup-$DATE.tar.gz" "${FILES[@]}" 2>/dev/null && \
    echo "LOCAL: /root/hermes-backup-$DATE.tar.gz"
fi

# Clean old local archives
ls -1t /root/hermes-backup-*.tar.gz 2>/dev/null | \
    tail -n +$((MAX_LOCAL+1)) | xargs rm -f 2>/dev/null
