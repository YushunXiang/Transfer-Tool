#!/bin/bash

# Configuration
OBS_DIR="obs://sai.liyl/xiangyushun"
TARGET_DIR="/inspire/hdd/project/robot-reasoning/xiangyushun-p-xiangyushun/yushun"
LOG_FILE="/var/log/robot-download.log"
TEMP_DIR="/tmp/robot_downloads"
ARCHIVE_PREFIX="data_part"
CHECK_INTERVAL=60  # Check for new files every 60 seconds

# Create necessary directories
mkdir -p "$TEMP_DIR"
mkdir -p "$TARGET_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to get all parts of a multipart archive
get_archive_parts() {
    local base_name="$1"
    rclone ls "$OBS_DIR" | grep "^.*${base_name}\.7z" | awk '{print $2}'
}

# Function to download file from OBS
download_file() {
    local file="$1"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        log "Downloading $file (attempt $((retry_count + 1)))"
        
        if rclone copy "$OBS_DIR/$file" "$TEMP_DIR/" --progress; then
            log "Successfully downloaded $file"
            return 0
        else
            log "Download failed for $file. Retrying..."
            ((retry_count++))
            sleep 10
        fi
    done
    
    log "ERROR: Failed to download $file after $max_retries attempts"
    return 1
}

# Function to delete file from OBS
delete_from_obs() {
    local file="$1"
    
    log "Deleting $file from OBS"
    if rclone delete "$OBS_DIR/$file"; then
        log "Successfully deleted $file from OBS"
        return 0
    else
        log "ERROR: Failed to delete $file from OBS"
        return 1
    fi
}

# Function to extract multipart archive (for tar+7z 打包方案)
extract_archive() {
    local base_name="$1"
    local first_part="${base_name}.7z.001"

    cd "$TEMP_DIR"

    log "Extracting archive (tar+7z): $base_name"
    # 1) 用 7zz x -so 把所有分卷流式解压到 stdout（它会自动读到 .002/.003…）
    # 2) 交给 tar 恢复原始目录结构和符号链接
    if 7zz x -so "$first_part" | tar -x -C "$TARGET_DIR"; then
        log "✔ Successfully extracted $base_name"
        rm -f ${base_name}.7z.*    # 清理本地分卷
        log "Cleaned up local parts for $base_name"
        return 0
    else
        log "ERROR: Failed to extract $base_name"
        return 1
    fi
}


# Function to process complete archive sets
process_archives() {
    # Get list of all files in OBS
    local files=$(rclone ls "$OBS_DIR" | grep "${ARCHIVE_PREFIX}.*\.7z" | awk '{print $2}')
    
    # Group files by archive base name
    declare -A archives
    
    while IFS= read -r file; do
        if [[ $file =~ ^(.*)\.7z(\.[0-9]+)?$ ]]; then
            base_name="${BASH_REMATCH[1]}"
            archives["$base_name"]=1
        fi
    done <<< "$files"
    
    # Process each archive set
    for base_name in "${!archives[@]}"; do
        log "Found archive set: $base_name"
        
        # Get all parts for this archive
        local parts=$(get_archive_parts "$base_name")
        local all_parts_present=true
        local part_count=0
        local downloaded_parts=()
        
        # Download all parts
        while IFS= read -r part; do
            if [ -n "$part" ]; then
                ((part_count++))
                if download_file "$part"; then
                    downloaded_parts+=("$part")
                else
                    all_parts_present=false
                    break
                fi
            fi
        done <<< "$parts"
        
        # If all parts downloaded successfully, extract and clean up
        if [ "$all_parts_present" = true ] && [ $part_count -gt 0 ]; then
            if extract_archive "$base_name"; then
                # Delete all parts from OBS after successful extraction
                for part in "${downloaded_parts[@]}"; do
                    delete_from_obs "$part"
                done
                log "Completed processing archive set: $base_name"
            else
                # Clean up failed extraction
                rm -f "$TEMP_DIR/${base_name}.7z".*
                log "Failed to extract archive set: $base_name"
            fi
        else
            # Clean up incomplete downloads
            for part in "${downloaded_parts[@]}"; do
                rm -f "$TEMP_DIR/$part"
            done
            
            if [ $part_count -eq 0 ]; then
                log "No parts found for archive: $base_name"
            else
                log "Failed to download all parts for archive: $base_name"
            fi
        fi
    done
}

# Main processing loop
main() {
    log "Starting robot-reasoning download service"
    
    while true; do
        log "Checking for new archives..."
        
        # Process any available archives
        process_archives
        
        # Wait before next check
        sleep $CHECK_INTERVAL
    done
}

# Signal handling for graceful shutdown
trap 'log "Received shutdown signal. Exiting..."; exit 0' SIGTERM SIGINT

# Start main process
main
