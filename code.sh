#!/bin/bash
#
# NFS / SFTP Sync Script
# Author: Aaditya
# Purpose: Sync files via rsync from 10.100.226.81 to 10.100.224.161 safely with logging and lock handling
#

# === Configuration ===
SOURCE_SERVER="10.100.226.81"
SOURCE_PATH="/sftp_home/sftp/sftp-files/"
DEST_SERVER="10.100.224.161"
DEST_PATH="/sftp_home/sftp/sftp-files/"
LOG_FILE="/home/vdarwatkar/log/nfs_sync.log"
LOCK_FILE="/home/vdarwatkar/nfs_sync.lock"

# === Safety: Always remove lock file on exit or interruption ===
trap 'rm -f "$LOCK_FILE"' EXIT

# === Check if script is already running ===
if [ -f "$LOCK_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Sync already in progress, exiting..." | tee -a "$LOG_FILE"
    exit 1
fi

# === Create lock file ===
touch "$LOCK_FILE"

# === Sync function with logging ===
do_sync() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Starting sync from $SOURCE_SERVER to $DEST_SERVER..." >> "$LOG_FILE"

    rsync -avz --delete \
        --exclude=".tmp" \
        --exclude="*.temp" \
        "$SOURCE_SERVER:$SOURCE_PATH" "$DEST_SERVER:$DEST_PATH" >> "$LOG_FILE" 2>&1

    SYNC_STATUS=$?
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Sync completed with status $SYNC_STATUS" >> "$LOG_FILE"
    return $SYNC_STATUS
}

# === Run sync ===
do_sync
RESULT=$?

# === Remove lock file (trap also ensures cleanup) ===
rm -f "$LOCK_FILE"

# === Exit with same result code ===
exit $RESULT
