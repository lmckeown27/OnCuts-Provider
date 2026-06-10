# CampusCuts System Storage & Cleanup Reference

Quick reference for monitoring disk usage and cleaning up server storage.

---

## Quick Health Check

### Overall Disk Usage
```bash
df -h
```

### Top Space Consumers
```bash
sudo du -h --max-depth=2 / 2>/dev/null | sort -rh | head -20
```

### Home Directory Usage
```bash
sudo du -h --max-depth=2 /home/ubuntu 2>/dev/null | sort -rh | head -20
```

---

## Docker

### Check Docker Disk Usage
```bash
sudo docker system df
sudo docker system df -v  # Verbose - shows all images
```

### List All Images
```bash
sudo docker images -a
```

### List All Containers (Including Stopped)
```bash
sudo docker ps -a
```

### List Running Containers Only
```bash
sudo docker ps
```

### Safe Cleanup (Removes Unused Images & Stopped Containers)
```bash
sudo docker system prune -a -f
```

### Aggressive Cleanup (Removes Everything Unused Including Volumes)
```bash
sudo docker system prune -a -f --volumes
```

### Remove Specific Image
```bash
sudo docker rmi IMAGE_ID
```

### Remove All Stopped Containers
```bash
sudo docker container prune -f
```

### Remove Dangling Images Only
```bash
sudo docker image prune -f
```

---

## NPM Cache

### Check NPM Cache Size
```bash
du -sh ~/.npm
du -sh ~/.npm/_cacache
```

### Clean NPM Cache
```bash
npm cache clean --force
```

### Remove Entire NPM Cache
```bash
rm -rf ~/.npm/_cacache
rm -rf ~/.npm/_npx
```

---

## Node Modules

### Find All node_modules Directories
```bash
find /home/ubuntu -name 'node_modules' -type d 2>/dev/null | xargs -I{} du -sh {} 2>/dev/null | sort -rh
```

### Remove node_modules (Reinstall Later)
```bash
rm -rf ~/CampusCuts/web-app/node_modules
rm -rf ~/CampusCuts/backend/node_modules
```

### Reinstall Dependencies
```bash
cd ~/CampusCuts/web-app && npm ci
cd ~/CampusCuts/backend && npm ci
```

---

## System Logs

### Check Journal Log Size
```bash
sudo journalctl --disk-usage
```

### Keep Only Last 7 Days of Logs
```bash
sudo journalctl --vacuum-time=7d
```

### Keep Only Last 3 Days of Logs
```bash
sudo journalctl --vacuum-time=3d
```

### Keep Only 100MB of Logs
```bash
sudo journalctl --vacuum-size=100M
```

### View Recent System Logs
```bash
sudo journalctl -n 100
```

### View Logs for Specific Service
```bash
sudo journalctl -u nginx -n 50
sudo journalctl -u docker -n 50
```

---

## APT Package Manager

### Check APT Cache Size
```bash
sudo du -sh /var/cache/apt
```

### Clean APT Cache
```bash
sudo apt clean
```

### Remove Unused Packages
```bash
sudo apt autoremove -y
```

### Full APT Cleanup
```bash
sudo apt clean && sudo apt autoremove -y
```

### Check for Available Updates
```bash
sudo apt update && apt list --upgradable
```

---

## PM2 Process Manager

### Check PM2 Log Sizes
```bash
du -sh ~/.pm2/logs
ls -lah ~/.pm2/logs
```

### Flush All PM2 Logs
```bash
pm2 flush
```

### View PM2 Processes
```bash
pm2 list
pm2 status
```

### View PM2 Logs
```bash
pm2 logs
pm2 logs --lines 100
```

---

## PostgreSQL Database

### Check Database Size
```bash
sudo -u postgres psql -d campuscuts -c "SELECT pg_size_pretty(pg_database_size('campuscuts'));"
```

### Check Table Sizes
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    relname as table_name, 
    pg_size_pretty(pg_total_relation_size(relid)) as size 
FROM pg_catalog.pg_statio_user_tables 
ORDER BY pg_total_relation_size(relid) DESC;
"
```

### Check PostgreSQL Data Directory Size
```bash
sudo du -sh /var/lib/postgresql
```

---

## Large Files Finder

### Find Files Larger Than 100MB
```bash
sudo find / -type f -size +100M 2>/dev/null | xargs -I{} ls -lh {} 2>/dev/null
```

### Find Files Larger Than 50MB in Home
```bash
find /home/ubuntu -type f -size +50M 2>/dev/null | xargs -I{} ls -lh {} 2>/dev/null
```

### Find Files Modified in Last 24 Hours (Large)
```bash
find /home/ubuntu -type f -mtime -1 -size +10M 2>/dev/null | xargs -I{} ls -lh {} 2>/dev/null
```

---

## Uploads Folder

### Check Uploads Size
```bash
du -sh ~/CampusCuts/backend/uploads
```

### List Upload Files
```bash
ls -lah ~/CampusCuts/backend/uploads
```

### Count Upload Files
```bash
find ~/CampusCuts/backend/uploads -type f | wc -l
```

---

## Git Repository

### Check Git Object Size
```bash
du -sh ~/CampusCuts/.git
```

### Clean Git (Remove Unreachable Objects)
```bash
cd ~/CampusCuts && git gc --prune=now
```

### View Large Files in Git History
```bash
cd ~/CampusCuts && git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | sed -n 's/^blob //p' | sort -rnk2 | head -20
```

---

## Snap Packages (Ubuntu)

### Check Snap Usage
```bash
du -sh /snap
snap list
```

### Remove Old Snap Versions
```bash
sudo snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do sudo snap remove "$snapname" --revision="$revision"; done
```

---

## Complete Cleanup Commands

### Quick Cleanup (Safe)
```bash
# Docker unused images
sudo docker system prune -f

# NPM cache
npm cache clean --force

# Journal logs (7 days)
sudo journalctl --vacuum-time=7d

# APT cache
sudo apt clean

# PM2 logs
pm2 flush
```

### Full Cleanup (More Aggressive)
```bash
# Docker everything unused
sudo docker system prune -a -f

# NPM full cache
rm -rf ~/.npm/_cacache ~/.npm/_npx

# Journal logs (3 days)
sudo journalctl --vacuum-time=3d

# APT full
sudo apt clean && sudo apt autoremove -y

# PM2 logs
pm2 flush

# Git cleanup
cd ~/CampusCuts && git gc --prune=now
```

---

## Automatic Cleanup

### Cleanup Script Location
```bash
/usr/local/bin/campuscuts-cleanup.sh
```

### View Cleanup Log
```bash
cat /var/log/campuscuts-cleanup.log
tail -50 /var/log/campuscuts-cleanup.log
```

### View Scheduled Cron Jobs
```bash
sudo crontab -l
```

### Run Cleanup Manually
```bash
sudo /usr/local/bin/campuscuts-cleanup.sh
```

### Edit Cleanup Schedule
```bash
sudo crontab -e
```

---

## Monitoring Commands

### Real-Time Disk I/O
```bash
iostat -x 1 5
```

### Real-Time Process Monitor
```bash
htop
# or
top
```

### Memory Usage
```bash
free -h
```

### Swap Usage
```bash
swapon --show
```

---

## Space Thresholds

| Usage | Status | Action |
|-------|--------|--------|
| < 50% | ✅ Healthy | No action needed |
| 50-70% | ⚠️ Moderate | Run quick cleanup |
| 70-85% | 🔶 Warning | Run full cleanup |
| > 85% | 🔴 Critical | Immediate cleanup + investigate |

---

## Common Space Hogs

| Location | Typical Size | Can Clean? |
|----------|--------------|------------|
| `/var/lib/docker` | 1-20GB | ✅ Prune unused |
| `~/.npm` | 500MB-2GB | ✅ Safe to clean |
| `/var/log/journal` | 500MB-5GB | ✅ Vacuum old logs |
| `/var/cache/apt` | 100-500MB | ✅ Safe to clean |
| `node_modules` | 200MB-1GB each | ⚠️ Need to reinstall |
| `/var/lib/postgresql` | Varies | ❌ Database data |
| `uploads/` | Varies | ⚠️ User content |

---

## Emergency: Disk Full

If disk is 100% full and system is unresponsive:

```bash
# 1. Clear journal logs immediately
sudo journalctl --vacuum-size=50M

# 2. Clear APT cache
sudo apt clean

# 3. Remove Docker build cache
sudo docker builder prune -a -f

# 4. Remove oldest large log files
sudo find /var/log -type f -name "*.log" -mtime +7 -delete

# 5. Check what's using space
df -h
sudo du -h --max-depth=1 / | sort -rh | head -10
```

---

