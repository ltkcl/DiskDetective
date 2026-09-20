# DiskDetective Storage Audit

Automated filesystem storage auditing, link mechanics analysis, and cold storage archiving utility for Red Hat Enterprise Linux (RHEL) systems.

## Business Case & Problem Statement

A shared RHEL file server hosting media production assets reaches critical disk capacity (96% utilization), preventing editors from saving new video renders. The storage exhaustion is caused by unindexed raw footage, stale temporary render files, and abandoned project directories consuming active volume space without operational visibility.

`DiskDetective` provides an automated system administration workflow and shell script that surveys disk utilization across mounted volumes, identifies files larger than 100 MB, isolates stale files unmodified for over 180 days, calculates reclaimable storage space, generates structured audit reports, and offloads stale assets to secondary archive storage.

## Architecture & Workflow

1. **Filesystem Survey:** Inspects block devices (`lsblk`), filesystem volume pressure (`df -h`), and top-level directory space consumption (`du`).

2. **Targeted Asset Discovery (`find`):**
   * Isolates large files exceeding 100 MB.
   * Isolates stale assets unmodified for over 180 days (`-mtime +180`).
   * Filters files by specific user ownership (`-user root` or unassigned accounts).

3. **Links Mechanics Analysis:** Demonstrates inode reference counts, link persistence, and disk space release behaviors when deleting source files linked via hard links vs. symbolic links.

4. **Automated Audit Pipeline (`disk_detective.sh`):** Assembles storage inspection metrics, formats output headers, suppresses error output (`2>/dev/null`), and writes execution logs to `/var/log/storage_audit.txt`.

5. **Cold Storage Offloading:** Formats and mounts a secondary virtual storage volume (`/mnt/cold_archive`) and transfers stale assets to reclaim primary storage capacity.

## File Architecture

```
/
├── usr/local/bin/
│   └── disk_detective.sh         # Primary storage auditing script
├── var/log/
│   └── storage_audit.txt         # Output audit report location
├── mnt/
│   └── cold_archive/             # Cold storage mount target for offloaded files
└── opt/
    └── cold_storage.img          # Loop storage volume container (if physical disk is absent)
```

## Setup & Implementation Guide

### Task 1: Filesystem Survey

Inspect storage block devices, partition tables, mounted filesystems, and top-level directory space usage:

```bash
# Display block devices and partition layouts
lsblk

# Display filesystem size, usage, and available space in human-readable format
df -h /

# Survey top-level directory disk consumption (suppressing access errors)
sudo du -sh /* 2>/dev/null | sort -hr | head -n 10
```

### Task 2: The Hunt (Targeted Search with `find`)

Locate space-consuming files while discarding standard errors:

```bash
# Locate all files larger than 100 MB across the filesystem
sudo find / -type f -size +100M -exec du -h {} + 2>/dev/null | sort -rh | head -n 10

# Locate all files unmodified in the last 180 days (stale data)
sudo find / -type f -mtime +180 -exec du -h {} + 2>/dev/null | sort -rh | head -n 20

# Locate all files owned by user 'root' larger than 50 MB
sudo find / -type f -user root -size +50M 2>/dev/null
```

### Task 3: Links Mechanics Investigation

Demonstrate hard link vs. symbolic link behavior, inode mapping, and disk space release:

```bash
# 1. Create temporary directory and source file
mkdir -p /tmp/link_test
echo "Critical video raw footage binary data" > /tmp/link_test/original_footage.raw

# 2. Create hard link and symbolic link
ln /tmp/link_test/original_footage.raw /tmp/link_test/hardlink_footage.raw
ln -s /tmp/link_test/original_footage.raw /tmp/link_test/symlink_footage.raw

# 3. Inspect inode numbers and link counts
ls -li /tmp/link_test/

# 4. Remove original file entry
rm -f /tmp/link_test/original_footage.raw

# 5. Verify link state and accessibility post-deletion
ls -li /tmp/link_test/
cat /tmp/link_test/hardlink_footage.raw  # Succeeds: data retained on disk
cat /tmp/link_test/symlink_footage.raw   # Fails: broken link error
```

### Task 4: Deploy Automated Auditing Engine

Deploy `/usr/local/bin/disk_detective.sh` to generate automated reports under `/var/log/storage_audit.txt`:

```bash
sudo bash -c 'cat << "EOF" > /usr/local/bin/disk_detective.sh
#!/bin/bash

REPORT="/var/log/storage_audit.txt"

{
    echo "=================================================="
    echo "         DISKDETECTIVE STORAGE AUDIT REPORT       "
    echo "         Generated: $(date)                       "
    echo "         Host: $(hostname)                        "
    echo "=================================================="
    echo ""

    echo "--- 1. FILESYSTEM PRESSURE SURVEY ---"
    df -h / | awk "NR==1 || NR==2"
    echo ""

    echo "--- 2. TOP 10 LARGEST FILES (>100MB) ---"
    find / -type f -size +100M -exec du -h {} + 2>/dev/null | sort -rh | head -n 10
    echo ""

    echo "--- 3. STALE FILES UNMODIFIED IN >180 DAYS ---"
    find / -type f -mtime +180 -exec du -h {} + 2>/dev/null | sort -rh | head -n 20
    echo ""

    echo "--- 4. RECLAIMABLE SPACE SUMMARY ---"
    STALE_COUNT=$(find / -type f -mtime +180 2>/dev/null | wc -l)
    STALE_SIZE=$(find / -type f -mtime +180 -exec du -ch {} + 2>/dev/null | grep total$ | awk "{print \$1}")
    [ -z "$STALE_SIZE" ] && STALE_SIZE="0B"
    
    echo "Total Stale Files Identified: $STALE_COUNT"
    echo "Total Reclaimable Disk Space: $STALE_SIZE"
    echo ""

    echo "=================================================="
    echo "              END OF STORAGE AUDIT                "
    echo "=================================================="
} > "$REPORT"

chmod 644 "$REPORT"
EOF'

# Grant execution rights and execute script
sudo chmod +x /usr/local/bin/disk_detective.sh
sudo /usr/local/bin/disk_detective.sh

# Display output report
sudo cat /var/log/storage_audit.txt
```

### Task 5: Cold Storage Archiving & Volume Mounting

Mount cold storage volume and transfer stale data to reclaim primary storage space:

```bash
# Create mount target
sudo mkdir -p /mnt/cold_archive

# Option A: Attach physical partition (e.g. /dev/sdb1)
# sudo mount /dev/sdb1 /mnt/cold_archive

# Option B: Create a 500MB Virtual Loop Volume (if secondary physical disk is unavailable)
sudo dd if=/dev/zero of=/opt/cold_storage.img bs=1M count=500
sudo mkfs.ext4 /opt/cold_storage.img
sudo mount -o loop /opt/cold_storage.img /mnt/cold_archive

# Archive identified stale temporary files to cold storage preserving path hierarchy
sudo mkdir -p /mnt/cold_archive/stale_files_archive
sudo find / -type f -mtime +180 -name "*.tmp" -exec cp --parents {} /mnt/cold_archive/stale_files_archive/ \; 2>/dev/null

# Confirm active mount points and free volume space
mount | grep /mnt/cold_archive
df -h /mnt/cold_archive
```

## Technical Analysis: Hard Links vs. Symbolic Links

| Feature | Hard Link (`ln file link`) | Symbolic Link (`ln -s file link`) |
| :--- | :--- | :--- |
| **Target Reference** | Points directly to the inode address on disk. | Points to the file system path string. |
| **Inode Number** | Shares the exact same inode number as source. | Assigned a new, unique inode number. |
| **Link Count Impact** | Increments inode reference count by 1. | Does not affect source inode link count. |
| **Source File Deletion** | File data remains intact; space is **not released** until link count reaches 0. | Link breaks immediately (`No such file or directory`); space is released. |
| **Cross-Filesystem Support**| Cannot span across different filesystems or mount points. | Can point across different filesystems and mount points. |

## Verification Procedures

1. **Verify Report Creation:**
   ```bash
   ls -l /var/log/storage_audit.txt
   ```
2. **Verify Loop Storage Mount:**
   ```bash
   df -h /mnt/cold_archive
   ```
3. **Verify Offloaded Files:**
   ```bash
   ls -la /mnt/cold_archive/stale_files_archive/
   ```
