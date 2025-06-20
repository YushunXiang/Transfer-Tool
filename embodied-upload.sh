#!/bin/bash
YOUR_DIR="tmp"
# Configuration
SOURCE_DIR="/inspire/hdd/project/embodied-intelligence/xiangyushun-p-xiangyushun/$YOUR_DIR"
OBS_DIR="obs://sai.liyl/$YOUR_DIR"
LOG_FILE="/var/log/embodied-upload.log"
ARCHIVE_PREFIX="data_part"
PART_SIZE="10g"  # 7z part size
TEMP_DIR="/tmp/embodied_archives"
RETRY_INTERVAL=30
MAX_RETRIES=999999  # Effectively infinite retries

# Create necessary directories
mkdir -p "$TEMP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check OBS storage availability
check_obs_space() {
    # Try to list files, if it fails, assume storage issue
    if ! rclone ls "$OBS_DIR" --max-depth 1 &>/dev/null; then
        return 1
    fi
    return 0
}

# Function to upload with retry logic
upload_with_retry() {
    local file="$1"
    local remote_path="$2"
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        log "Attempting to upload $file (attempt $((retry_count + 1)))"
        
        # Check if OBS is accessible
        if ! check_obs_space; then
            log "OBS appears to be full or inaccessible. Waiting $RETRY_INTERVAL seconds..."
            sleep $RETRY_INTERVAL
            ((retry_count++))
            continue
        fi
        
        # Attempt upload
        if obsutil cp "$file" "$remote_path"; then
            log "Successfully uploaded $file"
            return 0
        else
            log "Upload failed for $file. Waiting $RETRY_INTERVAL seconds before retry..."
            sleep $RETRY_INTERVAL
            ((retry_count++))
        fi
    done
    
    log "ERROR: Failed to upload $file after $MAX_RETRIES attempts"
    return 1
}

# Function to create archive and upload
process_directory() {
    local dir="$1"
    local relative_path="${dir#$SOURCE_DIR/}"
    local safe_name=$(echo "$relative_path" | tr '/' '_')
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local archive_base="${ARCHIVE_PREFIX}_${safe_name}_${timestamp}"
    
    log "Processing directory: $dir"
    
    # Create 7z archive with splitting
    cd "$TEMP_DIR"
    if 7zz a -v${PART_SIZE} -xr!@symlinks "${archive_base}.7z" "$dir" -mx=0; then
        log "Archive created successfully: ${archive_base}.7z"
        
        # Upload all parts
        for part in ${archive_base}.7z*; do
            if [ -f "$part" ]; then
                upload_with_retry "$TEMP_DIR/$part" "$OBS_DIR/"
                
                # Remove local part after successful upload
                if [ $? -eq 0 ]; then
                    rm -f "$TEMP_DIR/$part"
                    log "Removed local file: $part"
                fi
            fi
        done
    else
        log "ERROR: Failed to create archive for $dir"
    fi
}

# Main processing loop
main() {
    log "Starting embodied-intelligence upload service"
    
    while true; do
        # Find directories to process
        find "$SOURCE_DIR" -maxdepth 1 -type d | while read -r dir; do
            # Check if directory has a marker file indicating it's ready for transfer
            if [ -f "$dir/.ready_for_transfer" ]; then
                process_directory "$dir"
                
                # Remove marker file after processing
                rm -f "$dir/.ready_for_transfer"
                log "Processed and marked as transferred: $dir"
            fi
        done
        
        # Sleep before next scan
        sleep 20
    done
}

# Signal handling for graceful shutdown
trap 'log "Received shutdown signal. Exiting..."; exit 0' SIGTERM SIGINT

# Start main process
main