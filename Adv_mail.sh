#!/bin/bash
#
# Universal SFTP Bidirectional Sync Script with Email Alerts
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

# Email Configuration
EMAIL_RECIPIENT="admin@yourdomain.com"  # Change this to your email
EMAIL_FROM="noreply@yourdomain.com"     # Change this to sender email
SUCCESS_SUBJECT="SFTP Sync Success - $(hostname)"
FAILURE_SUBJECT="SFTP Sync FAILURE - $(hostname)"

# Rsync options for bidirectional sync
RSYNC_OPTS="-avz --update --checksum --exclude='.tmp' --exclude='*.temp' --exclude='.rsync-temp/'"

# === Safety: Always remove lock file on exit or interrupt ===
trap 'rm -f "$LOCK_FILE"' EXIT

# === Email Functions ===
send_success_email() {
    local email_body="SFTP Bidirectional Sync completed successfully on $(hostname) at $(date).

Server Details:
- Local Server: $LOCAL_IP
- Source Server: $SOURCE_SERVER  
- Destination Server: $DEST_SERVER
- Source Path: $SOURCE_PATH
- Destination Path: $DEST_PATH

Recent Log Output:
$(tail -n 20 "$LOG_FILE")

Full log available at: $LOG_FILE"

    echo "$email_body" | mailx -r "$EMAIL_FROM" -s "$SUCCESS_SUBJECT" "$EMAIL_RECIPIENT"
    
    if [ $? -eq 0 ]; then
        echo "$(date '+%F %T'): Success notification sent to $EMAIL_RECIPIENT" >> "$LOG_FILE"
    else
        echo "$(date '+%F %T'): WARNING: Failed to send success notification email" >> "$LOG_FILE"
    fi
}

send_failure_email() {
    local email_body="CRITICAL ALERT: SFTP Bidirectional Sync FAILED on $(hostname) at $(date).

Server Details:
- Local Server: $LOCAL_IP
- Source Server: $SOURCE_SERVER
- Destination Server: $DEST_SERVER  
- Source Path: $SOURCE_PATH
- Destination Path: $DEST_PATH

Error Details:
- Push Operation Result: $PUSH_RESULT
- Pull Operation Result: $PULL_RESULT

Recent Log Output (Last 30 lines):
$(tail -n 30 "$LOG_FILE")

Full log available at: $LOG_FILE

Please investigate immediately and resolve the sync issues."

    echo "$email_body" | mailx -r "$EMAIL_FROM" -s "$FAILURE_SUBJECT" "$EMAIL_RECIPIENT"
    
    if [ $? -eq 0 ]; then
        echo "$(date '+%F %T'): Failure notification sent to $EMAIL_RECIPIENT" >> "$LOG_FILE"
    else
        echo "$(date '+%F %T'): CRITICAL: Failed to send failure notification email" >> "$LOG_FILE"
    fi
}

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
    error_msg="$(date '+%F %T'): ERROR: Unknown host ($LOCAL_IP). Script must run on $SOURCE_SERVER or $DEST_SERVER"
    echo "$error_msg" | tee -a "$LOG_FILE"
    
    # Send error email for unknown host
    echo "CRITICAL ERROR: SFTP Sync script executed on unknown host.

Error: $error_msg

This script is configured to run only on:
- Source Server: $SOURCE_SERVER
- Destination Server: $DEST_SERVER

Current host: $LOCAL_IP

Please check script deployment and server configuration." | mailx -r "$EMAIL_FROM" -s "SFTP Sync ERROR - Unknown Host ($LOCAL_IP)" "$EMAIL_RECIPIENT"
    
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

# === Final Status and Email Notification ===
if [ $OVERALL_RESULT -eq 0 ]; then
    echo "$(date '+%F %T'): Bidirectional sync completed successfully." >> "$LOG_FILE"
    send_success_email
else
    echo "$(date '+%F %T'): Bidirectional sync completed with errors. Check log for details." >> "$LOG_FILE"
    send_failure_email
fi

rm -f "$LOCK_FILE"
exit $OVERALL_RESULT
