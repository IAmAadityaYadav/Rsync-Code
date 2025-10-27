#!/bin/bash
#
# Universal SFTP Bidirectional Sync Script
# Automatically detects which server it's running on and syncs in both directions
# Author: UNIX Team
#

# === Configuration ===
SOURCE_SERVER="IP"
DEST_SERVER="IP"
SOURCE_PATH="/sftp_home/sftp/sftp-files/"
DEST_PATH="/sftp_home/sftp/sftp_files/"
LOG_FILE="/var/log/nfs_sync.log"
LOCK_FILE="/var/log/nfs_sync.lock"

# Rsync options for bidirectional sync
RSYNC_OPTS="-avz --update --checksum --exclude='.tmp' --exclude='*.temp' --exclude='.rsync-temp/'"

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

# === Validate server ===
if [ "$LOCAL_IP" != "$SOURCE_SERVER" ] && [ "$LOCAL_IP" != "$DEST_SERVER" ]; then
    echo "$(date '+%F %T'): ERROR: Unknown host ($LOCAL_IP). Script must run on $SOURCE_SERVER or $DEST_SERVER" | tee -a "$LOG_FILE"
    rm -f "$LOCK_FILE"
    exit 1
fi

echo "$(date '+%F %T'): Starting bidirectional sync from $LOCAL_IP..." >> "$LOG_FILE"

# === Function to perform sync operation ===
perform_sync() {
    local source_loc="$1"
    local dest_loc="$2"
    local direction="$3"
    
    echo "$(date '+%F %T'): Syncing $direction: $source_loc -> $dest_loc" >> "$LOG_FILE"
    
    rsync $RSYNC_OPTS "$source_loc" "$dest_loc" >> "$LOG_FILE" 2>&1
    local result=$?
    
    if [ $result -eq 0 ]; then
        echo "$(date '+%F %T'): $direction sync completed successfully" >> "$LOG_FILE"
    else
        echo "$(date '+%F %T'): $direction sync failed with status $result" >> "$LOG_FILE"
    fi
    
    return $result
}

# === Bidirectional Sync Logic ===
OVERALL_RESULT=0

if [ "$LOCAL_IP" = "$SOURCE_SERVER" ]; then
    # Running on SOURCE server
    echo "$(date '+%F %T'): Running on SOURCE server, performing bidirectional sync..." >> "$LOG_FILE"
    
    # First: Push local changes to remote (SOURCE -> DEST)
    perform_sync "$SOURCE_PATH" "$DEST_SERVER:$DEST_PATH" "PUSH"
    PUSH_RESULT=$?
    
    # Second: Pull remote changes to local (DEST -> SOURCE)  
    perform_sync "$DEST_SERVER:$DEST_PATH" "$SOURCE_PATH" "PULL"
    PULL_RESULT=$?
    
    # Overall result
    if [ $PUSH_RESULT -ne 0 ] || [ $PULL_RESULT -ne 0 ]; then
        OVERALL_RESULT=1
    fi

elif [ "$LOCAL_IP" = "$DEST_SERVER" ]; then
    # Running on DEST server
    echo "$(date '+%F %T'): Running on DEST server, performing bidirectional sync..." >> "$LOG_FILE"
    
    # First: Push local changes to remote (DEST -> SOURCE)
    perform_sync "$DEST_PATH" "$SOURCE_SERVER:$SOURCE_PATH" "PUSH"
    PUSH_RESULT=$?
    
    # Second: Pull remote changes to local (SOURCE -> DEST)
    perform_sync "$SOURCE_SERVER:$SOURCE_PATH" "$DEST_PATH" "PULL"
    PULL_RESULT=$?
    
    # Overall result
    if [ $PUSH_RESULT -ne 0 ] || [ $PULL_RESULT -ne 0 ]; then
        OVERALL_RESULT=1
    fi
fi

# === Final Status ===
if [ $OVERALL_RESULT -eq 0 ]; then
    echo "$(date '+%F %T'): Bidirectional sync completed successfully." >> "$LOG_FILE"
else
    echo "$(date '+%F %T'): Bidirectional sync completed with errors. Check log for details." >> "$LOG_FILE"
fi

rm -f "$LOCK_FILE"
exit $OVERALL_RESULT
