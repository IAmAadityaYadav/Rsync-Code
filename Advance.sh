#!/bin/bash
#
# Universal SFTP Bidirectional Sync Script with Comprehensive Monitoring
# Features: NFS checks, file count comparison, error detection, email alerts, heartbeat
# Author: UNIX Team
#

# === Configuration ===
SOURCE_SERVER="IP"
DEST_SERVER="IP"
SOURCE_PATH="/sftp_home/sftp/sftp-files/"
DEST_PATH="/sftp_home/sftp/sftp_files/"
LOG_FILE="/var/log/nfs_sync.log"
LOCK_FILE="/var/lock/nfs_sync.lock"
HEARTBEAT_FILE="/var/log/nfs_sync_heartbeat"

# Email Configuration
ALERT_EMAIL="admin@company.com"
EMAIL_FROM="nfs-sync@$(hostname -f)"
SMTP_SERVER="localhost"

# Monitoring Thresholds
FILE_COUNT_DIFF_THRESHOLD=10  # Alert if file count difference > 10
MAX_LOG_ERRORS=5              # Alert if more than 5 errors in recent logs

# Rsync options for bidirectional sync
RSYNC_OPTS="-avz --update --checksum --exclude='.tmp' --exclude='*.temp' --exclude='.rsync-temp/'"

# === Utility Functions ===

# Function to send email alerts [web:36][web:39]
send_alert() {
    local subject="$1"
    local message="$2"
    local priority="${3:-normal}"
    
    local datetime=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname -f)
    
    # Create email content
    local email_content="Alert Time: $datetime
Server: $hostname
Script: NFS Bidirectional Sync Monitor

$message

---
This is an automated alert from the NFS sync monitoring system.
"
    
    # Send email using mail command [web:36][web:47]
    echo "$email_content" | mail -s "[$priority] $subject" \
        -a "From: $EMAIL_FROM" \
        "$ALERT_EMAIL" 2>/dev/null || {
        echo "$(date '+%F %T'): ERROR: Failed to send email alert" >> "$LOG_FILE"
    }
    
    echo "$(date '+%F %T'): ALERT SENT: $subject" >> "$LOG_FILE"
}

# Function to check if NFS mount is present and writable [web:30][web:31]
check_nfs_mount() {
    local mount_path="$1"
    local errors=()
    
    # Check if path is mounted
    if ! mountpoint -q "$mount_path" 2>/dev/null; then
        errors+=("$mount_path is not a mountpoint")
    fi
    
    # Check if it's an NFS mount
    if ! mount | grep -q "$mount_path.*nfs"; then
        errors+=("$mount_path is not an NFS mount")
    fi
    
    # Check if mount is writable [web:31]
    local test_file="$mount_path/.nfs_write_test_$$"
    if ! touch "$test_file" 2>/dev/null; then
        errors+=("$mount_path is not writable")
    else
        rm -f "$test_file" 2>/dev/null
    fi
    
    # Check mount status in /proc/mounts
    if mount | grep "$mount_path" | grep -q "ro,"; then
        errors+=("$mount_path is mounted read-only")
    fi
    
    if [ ${#errors[@]} -gt 0 ]; then
        local error_msg=$(IFS=$'\n'; echo "${errors[*]}")
        echo "$(date '+%F %T'): NFS MOUNT ERRORS for $mount_path:" >> "$LOG_FILE"
        echo "$error_msg" >> "$LOG_FILE"
        return 1
    fi
    
    echo "$(date '+%F %T'): NFS mount check passed for $mount_path" >> "$LOG_FILE"
    return 0
}

# Function to count files in directory
count_files() {
    local path="$1"
    local server="$2"
    
    if [ "$server" = "local" ]; then
        find "$path" -type f 2>/dev/null | wc -l
    else
        ssh "$server" "find '$path' -type f 2>/dev/null | wc -l" 2>/dev/null || echo "0"
    fi
}

# Function to compare file counts between source and destination
compare_file_counts() {
    local source_path="$1"
    local dest_path="$2"
    local source_server="$3"
    local dest_server="$4"
    
    echo "$(date '+%F %T'): Comparing file counts..." >> "$LOG_FILE"
    
    local source_count dest_count
    
    if [ "$source_server" = "local" ]; then
        source_count=$(count_files "$source_path" "local")
    else
        source_count=$(count_files "$source_path" "$source_server")
    fi
    
    if [ "$dest_server" = "local" ]; then
        dest_count=$(count_files "$dest_path" "local")
    else
        dest_count=$(count_files "$dest_path" "$dest_server")
    fi
    
    local diff=$((source_count - dest_count))
    local abs_diff=${diff#-}  # Get absolute value
    
    echo "$(date '+%F %T'): File count - Source: $source_count, Destination: $dest_count, Difference: $diff" >> "$LOG_FILE"
    
    if [ "$abs_diff" -gt "$FILE_COUNT_DIFF_THRESHOLD" ]; then
        send_alert "File Count Discrepancy Detected" \
            "Significant file count difference detected:
Source ($source_server:$source_path): $source_count files
Destination ($dest_server:$dest_path): $dest_count files
Difference: $diff files (threshold: $FILE_COUNT_DIFF_THRESHOLD)

This may indicate sync issues or data inconsistency." "HIGH"
        return 1
    fi
    
    return 0
}

# Function to detect rsync errors in recent logs [web:38]
detect_rsync_errors() {
    local log_file="$1"
    local error_count=0
    local errors=()
    
    # Look for rsync errors in the last 100 lines of log
    if [ -f "$log_file" ]; then
        # Common rsync error patterns
        while IFS= read -r line; do
            errors+=("$line")
            ((error_count++))
        done < <(tail -100 "$log_file" | grep -E "(rsync.*error|rsync.*failed|rsync.*No such file|rsync.*Permission denied|rsync.*Connection refused)" | tail -10)
        
        if [ "$error_count" -gt 0 ]; then
            echo "$(date '+%F %T'): Found $error_count rsync errors in recent logs" >> "$LOG_FILE"
            
            if [ "$error_count" -ge "$MAX_LOG_ERRORS" ]; then
                local error_summary=$(IFS=$'\n'; echo "${errors[*]}")
                send_alert "Multiple Rsync Errors Detected" \
                    "Found $error_count rsync errors in recent logs:

$error_summary

Please check the sync processes and resolve any underlying issues." "HIGH"
                return 1
            fi
        fi
    fi
    
    return 0
}

# Function to update heartbeat timestamp
update_heartbeat() {
    local status="$1"
    local message="$2"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname -f)
    
    cat > "$HEARTBEAT_FILE" << EOF
{
  "timestamp": "$timestamp",
  "hostname": "$hostname",
  "status": "$status",
  "message": "$message",
  "last_sync_result": "$OVERALL_RESULT"
}
EOF
    
    echo "$(date '+%F %T'): Heartbeat updated - Status: $status" >> "$LOG_FILE"
}

# Function to acquire exclusive lock using flock
acquire_lock() {
    exec 200>"$LOCK_FILE" || {
        echo "$(date '+%F %T'): ERROR: Cannot open lock file $LOCK_FILE" | tee -a "$LOG_FILE"
        exit 1
    }
    
    if ! flock -n 200; then
        echo "$(date '+%F %T'): Sync already in progress, exiting..." | tee -a "$LOG_FILE"
        exec 200>&-
        exit 1
    fi
    
    echo "$(date '+%F %T'): Lock acquired successfully" >> "$LOG_FILE"
}

# Function to release lock
release_lock() {
    if [ -n "$1" ]; then
        echo "$(date '+%F %T'): $1" >> "$LOG_FILE"
    fi
    exec 200>&-
    echo "$(date '+%F %T'): Lock released" >> "$LOG_FILE"
}

# Safety: Always release lock on exit or interrupt
trap 'release_lock "Script interrupted or exited"; update_heartbeat "interrupted" "Script was interrupted or exited unexpectedly"' EXIT INT TERM

# === Main Execution ===

# Acquire lock first
acquire_lock

# Determine local server IP
LOCAL_IP=$(hostname -I | awk '{print $1}')

# Validate server
if [ "$LOCAL_IP" != "$SOURCE_SERVER" ] && [ "$LOCAL_IP" != "$DEST_SERVER" ]; then
    send_alert "Configuration Error" \
        "Script is running on unknown host ($LOCAL_IP).
Script must run on $SOURCE_SERVER or $DEST_SERVER" "HIGH"
    exit 1
fi

echo "$(date '+%F %T'): Starting bidirectional sync with monitoring from $LOCAL_IP..." >> "$LOG_FILE"

# === Pre-Sync Checks ===

echo "$(date '+%F %T'): Performing pre-sync checks..." >> "$LOG_FILE"

# Check NFS mounts [web:30][web:31]
nfs_errors=0

if [ "$LOCAL_IP" = "$SOURCE_SERVER" ]; then
    if ! check_nfs_mount "$(dirname "$SOURCE_PATH")"; then
        ((nfs_errors++))
    fi
elif [ "$LOCAL_IP" = "$DEST_SERVER" ]; then
    if ! check_nfs_mount "$(dirname "$DEST_PATH")"; then
        ((nfs_errors++))
    fi
fi

# Check for recent rsync errors
if ! detect_rsync_errors "$LOG_FILE"; then
    echo "$(date '+%F %T'): WARNING: Recent rsync errors detected" >> "$LOG_FILE"
fi

# If critical NFS errors, abort sync
if [ "$nfs_errors" -gt 0 ]; then
    send_alert "NFS Mount Check Failed" \
        "Critical NFS mount issues detected. Sync operation aborted to prevent data loss.
Please resolve NFS mount issues before retrying." "CRITICAL"
    update_heartbeat "failed" "NFS mount checks failed"
    exit 1
fi

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
        send_alert "Rsync Operation Failed" \
            "Rsync $direction operation failed with exit code $result.
Source: $source_loc
Destination: $dest_loc

Check logs at $LOG_FILE for detailed error information." "HIGH"
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
    
    # Compare file counts
    compare_file_counts "$SOURCE_PATH" "$DEST_PATH" "local" "$DEST_SERVER"
    COUNT_RESULT=$?
    
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
    
    # Compare file counts
    compare_file_counts "$SOURCE_PATH" "$DEST_PATH" "$SOURCE_SERVER" "local"
    COUNT_RESULT=$?
    
    # Overall result
    if [ $PUSH_RESULT -ne 0 ] || [ $PULL_RESULT -ne 0 ]; then
        OVERALL_RESULT=1
    fi
fi

# === Post-Sync Monitoring ===

# Check for new rsync errors after sync
detect_rsync_errors "$LOG_FILE"

# === Final Status and Alerting ===

if [ $OVERALL_RESULT -eq 0 ]; then
    echo "$(date '+%F %T'): Bidirectional sync completed successfully." >> "$LOG_FILE"
    update_heartbeat "success" "Bidirectional sync completed successfully"
else
    echo "$(date '+%F %T'): Bidirectional sync completed with errors. Check log for details." >> "$LOG_FILE"
    update_heartbeat "failed" "Bidirectional sync completed with errors"
    
    # Send summary alert for failed sync
    send_alert "Sync Operation Failed" \
        "Bidirectional sync operation completed with errors.
Server: $(hostname -f)
Log file: $LOG_FILE

Please review the logs and resolve any issues." "HIGH"
fi

exit $OVERALL_RESULT
