# How to Auto-Backup Hermes Agent Config to GitHub

Step-by-step guide to automatically backup your **Hermes Agent** configuration, skills, and sessions to a **private GitHub repository** every day.

## What This Backs Up

| File | Description | Pushed to GitHub? | Local Archive? |
|------|-------------|-------------------|----------------|
| `config.yaml` | Provider settings, tools, integrations | ✅ Yes | ✅ Yes |
| `skills/` | Your custom skills and workflows | ✅ Yes | ✅ Yes |
| `.env` | API keys & secrets | ❌ **Never** | ✅ Yes |
| `auth.json` | Authentication tokens | ❌ **Never** | ✅ Yes |
| `state.db` | Session transcripts & chat history | ❌ **Never** | ✅ Yes |

> 🔒 **Security:** `.env`, `auth.json`, and `state.db` are saved in a local `.tar.gz` archive **only**. They are never pushed to GitHub, even to a private repo.

## Setup

### 1. Create a Private Repo

```bash
gh repo create hermes-backup --private --description "Hermes Agent config backup"
```

### 2. Clone to Your Server

**Via SSH:**
```bash
cd /root
git clone git@github.com:YOUR_USERNAME/hermes-backup.git
```

**Via HTTPS (if using PAT):**
```bash
cd /root
git clone https://YOUR_USERNAME:YOUR_TOKEN@github.com/YOUR_USERNAME/hermes-backup.git
```

### 3. Create the Backup Script

Create `~/.hermes/scripts/hermes-backup.sh`:

```bash
#!/bin/bash
HERMES_HOME="$HOME/.hermes"
GIT_REPO="/root/hermes-backup"
DATE=$(date +%Y-%m-%d)

# Push safe files to GitHub (config.yaml & skills only)
mkdir -p "$GIT_REPO/config" "$GIT_REPO/skills"
cp "$HERMES_HOME/config.yaml" "$GIT_REPO/config/" 2>/dev/null
cp -r "$HERMES_HOME/skills/"* "$GIT_REPO/skills/" 2>/dev/null

cd "$GIT_REPO" || exit 1
if [ -n "$(git status --porcelain)" ]; then
    git add .
    git commit -m "backup $DATE"
    git push origin HEAD:main
fi

# Full local backup (includes .env, auth.json, state.db — stays on server only)
tar -czf "/root/hermes-backup-$DATE.tar.gz" \
  "$HERMES_HOME/config.yaml" "$HERMES_HOME/.env" \
  "$HERMES_HOME/auth.json" "$HERMES_HOME/state.db" \
  "$HERMES_HOME/skills" 2>/dev/null
```

Make it executable:
```bash
chmod +x ~/.hermes/scripts/hermes-backup.sh
```

### 3b. Create .gitignore

Create `/root/hermes-backup/.gitignore` to keep secrets out of git:

```bash
cat > /root/hermes-backup/.gitignore << 'EOF'
# Secrets - never pushed to GitHub
.env
*.tar.gz
auth.json
config/auth.json
state.db
sessions/state.db
*.tmp
*.log
EOF

cd /root/hermes-backup && git add .gitignore && git commit -m "add .gitignore"
```

### 4. Schedule with Cron

Using Hermes Agent scheduler:

```bash
hermes cron create \
  --name "hermes-backup" \
  --schedule "0 19 * * *" \
  --script ~/.hermes/scripts/hermes-backup.sh \
  --no-agent
```

This runs the backup daily at **7 PM UTC**.

### 5. Test It

```bash
bash ~/.hermes/scripts/hermes-backup.sh
cd /root/hermes-backup && git log --oneline
```

## What to Expect

After setup, every day at 7 PM UTC:
1. Hermes config/skills/sessions are copied to the repo folder
2. Changes are committed and pushed as `backup YYYY-MM-DD`
3. A full archive (including `.env`) is saved locally at `/root/hermes-backup-YYYY-MM-DD.tar.gz`
4. Local archives older than 7 days are deleted

## Restore

### From GitHub (no .env)
```bash
cd /root
git clone git@github.com:YOUR_USERNAME/hermes-backup.git
cp hermes-backup/config/config.yaml ~/.hermes/
cp hermes-backup/sessions/state.db ~/.hermes/
cp -r hermes-backup/skills/* ~/.hermes/skills/
```

### From Local Archive (with .env)
```bash
tar -xzf /root/hermes-backup-YYYY-MM-DD.tar.gz -C ~/
```

## Security Notes

- **Keep the GitHub repo PRIVATE** — it contains your config and skills
- `.env`, `auth.json`, and `state.db` are **never** committed to Git — they exist only in local `.tar.gz` archives on your server
- State.db contains **all your chat transcripts** — treat it like a private message history
- Auth.json contains **OAuth tokens** — rotate immediately if your repo is ever exposed
- If you accidentally expose a repo, rotate ALL your API keys and tokens immediately
- The local `.tar.gz` archive stays on your server only — clean old ones with `rm /root/hermes-backup-*.tar.gz`

## Requirements

- [Hermes Agent](https://hermes-agent.nousresearch.com) installed
- GitHub CLI (`gh`) authenticated
- SSH key **or** GitHub classic PAT (see below)

## GitHub Authentication Setup

Your server needs to authenticate with GitHub to push backups. Choose **one** method:

### Option A: SSH Key (Recommended)

```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "your-email@example.com"

# Add to SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Show public key — copy this to GitHub
cat ~/.ssh/id_ed25519.pub
```

Then add the key at **GitHub → Settings → SSH and GPG keys → New SSH key**.

### Option B: Classic PAT (Token)

If you can't or don't want to use SSH, create a classic Personal Access Token:

1. Go to **GitHub.com → Settings → Developer settings → Personal access tokens → Tokens (classic)**
2. Click **Generate new token (classic)**
3. Give it a name (e.g., `hermes-backup`)
4. Set expiration (recommended: 90 days or No expiration for long-term)
5. Select scope: **`repo`** (Full control of private repositories)
6. Click **Generate token**
7. **Copy the token now** — you won't see it again!

Then store the token on your server:

```bash
# Save token for git HTTPS access
git config --global credential.helper store
echo "https://YOUR_USERNAME:YOUR_TOKEN@github.com" > ~/.git-credentials
chmod 600 ~/.git-credentials
```

Or use it directly when cloning:

```bash
git clone https://YOUR_USERNAME:YOUR_TOKEN@github.com/YOUR_USERNAME/hermes-backup.git
```

> ⚠️ **Keep your token secret.** Anyone with this token can read/write your private repos.

### Verify Auth Works

```bash
# SSH method
ssh -T git@github.com
# Expected output: "Hi YOUR_USERNAME! You've successfully authenticated..."

# PAT method
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user
```

## License

MIT
