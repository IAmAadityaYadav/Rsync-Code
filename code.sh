#!/bin/bash
#
# Universal SFTP Sync Script
# Automatically detects which server it's running on
# Author: UNIX Team
#

# === Configuration ===
SOURCE_SERVER="IP"
DEST_SERVER="IP"
SOURCE_PATH="/sftp_home/sftp/sftp-files/"
DEST_PATH="/sftp_home/sftp/sftp-files/"
LOG_FILE="/var/log/nfs_sync.log"
LOCK_FILE="/var/log/nfs_sync.lock"

# === Safety: Always remove lock file on exit or interrupt ===
trap 'rm -f "$LOCK_FILE"' EXIT

# === Check if already running ===
if [ -f "$LOCK_FILE" ]; then
    echo "$(date '+%F %T'): Sync already in progress, exiting..." | tee -a "$LOG_FILE"
    exit 1
fi

touch "$LOCK_FILE"

# === Determine local server IP ===
LOCAL_IP=$(hostname -I | awk '{print $1}')

# === Choose direction ===
if [ "$LOCAL_IP" = "$SOURCE_SERVER" ]; then
    SYNC_MODE="push"
elif [ "$LOCAL_IP" = "$DEST_SERVER" ]; then
    SYNC_MODE="pull"
else
    echo "$(date '+%F %T'): ERROR: Unknown host ($LOCAL_IP). Script must run on $SOURCE_SERVER or $DEST_SERVER" | tee -a "$LOG_FILE"
    rm -f "$LOCK_FILE"
    exit 1
fi

echo "$(date '+%F %T'): Starting sync in $SYNC_MODE mode..." >> "$LOG_FILE"

# === Run sync ===
if [ "$SYNC_MODE" = "push" ]; then
    rsync -avz --delete \
        --exclude=".tmp" \
        --exclude="*.temp" \
        "$SOURCE_PATH" "$DEST_SERVER:$DEST_PATH" >> "$LOG_FILE" 2>&1
else
    rsync -avz --delete \
        --exclude=".tmp" \
        --exclude="*.temp" \
        "$SOURCE_SERVER:$SOURCE_PATH" "$DEST_PATH" >> "$LOG_FILE" 2>&1
fi

RESULT=$?
if [ $RESULT -eq 0 ]; then
    echo "$(date '+%F %T'): Sync completed successfully." >> "$LOG_FILE"
else
    echo "$(date '+%F %T'): Sync failed with status $RESULT" >> "$LOG_FILE"
fi

rm -f "$LOCK_FILE"
exit $RESULT
