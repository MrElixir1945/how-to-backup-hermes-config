# Hermes Agent Auto-Backup & Restore

Backup & restore Hermes Agent ke device lokal (CT/VM/server) via SSH. **No cloud, no third party.**

---

## 🚀 Cara Termudah — 1 Script Doang

Buat server Hermes baru? Tinggal curl & jalanin:

```bash
curl -o setup-hermes.sh https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/setup-hermes.sh
bash setup-hermes.sh
```

**Yang terjadi:**
1. Tanya IP backup device → tes koneksi SSH
2. Restore data (kalo ada backup)
3. Bikin file config biar tau IP tujuan
4. Pasang cron backup otomatis (bisa atur jam)
5. Backup pertama bisa langsung jalan

---

## 🛠️ Cara Manual (Step by Step)

Kalo mau setup manual atau paham cara kerja:

### 1. Backup Script

```bash
# Download script backup
curl -o ~/.hermes/scripts/hermes-backup.sh https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/hermes-backup.sh
chmod +x ~/.hermes/scripts/hermes-backup.sh

# Buat config — isi IP backup device lu
echo 'BACKUP_IP=192.168.1.100' > ~/.hermes/scripts/backup-target.conf
echo 'BACKUP_USER=root' >> ~/.hermes/scripts/backup-target.conf
```

### 2. Test

```bash
bash ~/.hermes/scripts/hermes-backup.sh
```

### 3. Auto Backup (Cron)

```bash
hermes cron create \
  --name "hermes-backup" \
  --schedule "0 3 * * *" \
  --script hermes-backup.sh \
  --no-agent
```

> ⏰ Cron pake timezone server. Kalo server UTC, `0 19 * * *` = jam 3 pagi WITA.

---

## ♻️ Restore Data

Kalo server ilang / ganti baru, tinggal restore:

```bash
curl -o restore.sh https://raw.githubusercontent.com/MrElixir1945/how-to-backup-hermes-config/main/hermes-restore.sh
bash restore.sh
```

Nanti bakal tanya:
1. **Pilih backup** — milih dari daftar folder backup yang ada
2. **IP server tujuan** — server baru yang mau dipulihin
3. **Konfirmasi** — ketik RESTORE, beres ✅

---

## 📁 Apa Aja Yang Dibackup?

| Item | Deskripsi | Backup | Lokal |
|------|-----------|--------|-------|
| `config.yaml` | Setting provider, tools, dll | ✅ | ✅ |
| `skills/` | Skill & workflow | ✅ | ✅ |
| `.env` | API keys & secrets | ✅ (via SSH) | ✅ |
| `auth.json` | Token autentikasi | ✅ (via SSH) | ✅ |
| `state.db` | Riwayat chat | ✅ | ✅ |
| `mnemosyne/` | Memori jangka panjang | ✅ | ❌ |
| `cron/` | Jadwal otomatis | ✅ | ❌ |
| Source code | Kode Hermes Agent | ✅ | ❌ |

Semua file ada di `/root/backups/<hostname>/` di backup device.

---

## 🧠 Multi Server

Pake script yang sama di semua server Hermes. Tinggal tambahin SSH key masing-masing ke backup device. Otomatis kebikin folder sendiri-sendiri per hostname.

---

## 🔒 Keamanan

- Semua di **jaringan lokal** — gak ada yang ke cloud
- Koneksi via SSH key — gak pake password
- Backup lewat `rsync` — data terenkripsi tunnel SSH

---

## 📜 License

MIT
