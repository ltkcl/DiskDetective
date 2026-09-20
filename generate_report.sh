#!/bin/bash
# Storage Audit Generator for RHEL Shared File Server

REPORT="storage_audit.txt"
TARGET_DIR="/mnt/shared"

# Clear existing report
> "$REPORT"

echo "==================================================" | tee -a "$REPORT"
echo "           STORAGE AUDIT REPORT                  " | tee -a "$REPORT"
echo "           Generated: $(date)                    " | tee -a "$REPORT"
echo "==================================================" | tee -a "$REPORT"
echo "" >> "$REPORT"

# Section 1: Filesystem Summary
echo "--- 1. FILESYSTEM OVERVIEW ---" >> "$REPORT"
df -h "$TARGET_DIR" 2>/dev/null >> "$REPORT"
echo "" >> "$REPORT"

# Section 2: Top 10 Largest Files
echo "--- 2. TOP 10 LARGEST FILES (>100MB) ---" >> "$REPORT"
echo "Command: find $TARGET_DIR -type f -size +100M -exec du -h {} + 2>/dev/null | sort -rh | head -n 10" >> "$REPORT"
find "$TARGET_DIR" -type f -size +100M -exec du -h {} + 2>/dev/null | sort -rh | head -n 10 >> "$REPORT"
echo "" >> "$REPORT"

# Section 3: Stale File List (Not modified in > 180 days)
echo "--- 3. STALE FILE LIST (>180 DAYS OLD) ---" >> "$REPORT"
echo "Command: find $TARGET_DIR -type f -mtime +180 -exec ls -lh {} + 2>/dev/null" >> "$REPORT"
find "$TARGET_DIR" -type f -mtime +180 -exec ls -lh {} + 2>/dev/null >> "$REPORT"
echo "" >> "$REPORT"

# Section 4: Reclaimable Space Metrics
echo "--- 4. RECLAIMABLE SPACE METRICS ---" >> "$REPORT"
STALE_COUNT=$(find "$TARGET_DIR" -type f -mtime +180 2>/dev/null | wc -l)
STALE_SIZE=$(find "$TARGET_DIR" -type f -mtime +180 -exec du -ch {} + 2>/dev/null | grep total$ | awk '{print $1}')

echo "Total Stale Files Found: $STALE_COUNT" | tee -a "$REPORT"
echo "Total Reclaimable Space: ${STALE_SIZE:-0B}" | tee -a "$REPORT"
echo "==================================================" >> "$REPORT"
