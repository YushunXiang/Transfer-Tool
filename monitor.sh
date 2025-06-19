#!/bin/bash

# Configuration
OBS_DIR="obs://sai.liyl/xiangyushun"
UPLOAD_LOG="/var/log/embodied-upload.log"
DOWNLOAD_LOG="/var/log/robot-download.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check service status
check_service() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✓ $service is running${NC}"
    else
        echo -e "${RED}✗ $service is not running${NC}"
    fi
}

# Function to get OBS storage info
get_obs_info() {
    echo -e "\n${YELLOW}OBS Storage Information:${NC}"
    
    # Count files
    local file_count=$(rclone ls "$OBS_DIR" 2>/dev/null | wc -l)
    echo "Files in OBS: $file_count"
    
    # Get total size
    local total_size=$(rclone size "$OBS_DIR" 2>/dev/null | grep "Total size:" | cut -d: -f2)
    echo "Total size: $total_size"
    
    # List recent files
    echo -e "\nRecent files (last 10):"
    rclone ls "$OBS_DIR" 2>/dev/null | tail -10
}

# Function to show recent log entries
show_recent_logs() {
    local log_file="$1"
    local service_name="$2"
    
    if [ -f "$log_file" ]; then
        echo -e "\n${YELLOW}Recent $service_name logs:${NC}"
        tail -5 "$log_file"
    fi
}

# Function to calculate transfer statistics
show_transfer_stats() {
    echo -e "\n${YELLOW}Transfer Statistics:${NC}"
    
    if [ -f "$UPLOAD_LOG" ]; then
        local uploads_today=$(grep "$(date +%Y-%m-%d)" "$UPLOAD_LOG" | grep -c "Successfully uploaded")
        local upload_errors=$(grep "$(date +%Y-%m-%d)" "$UPLOAD_LOG" | grep -c "ERROR")
        echo "Uploads today: $uploads_today (Errors: $upload_errors)"
    fi
    
    if [ -f "$DOWNLOAD_LOG" ]; then
        local downloads_today=$(grep "$(date +%Y-%m-%d)" "$DOWNLOAD_LOG" | grep -c "Successfully downloaded")
        local download_errors=$(grep "$(date +%Y-%m-%d)" "$DOWNLOAD_LOG" | grep -c "ERROR")
        echo "Downloads today: $downloads_today (Errors: $download_errors)"
    fi
}

# Main monitoring display
clear
echo -e "${GREEN}=== Data Transfer Monitoring Dashboard ===${NC}"
echo "Timestamp: $(date)"

# Check services
echo -e "\n${YELLOW}Service Status:${NC}"
check_service "embodied-upload.service"
check_service "robot-download.service"

# Show OBS information
get_obs_info

# Show transfer statistics
show_transfer_stats

# Show recent logs
show_recent_logs "$UPLOAD_LOG" "Upload"
show_recent_logs "$DOWNLOAD_LOG" "Download"

# Continuous monitoring option
if [ "$1" == "--watch" ]; then
    echo -e "\n${YELLOW}Watching for updates (Ctrl+C to exit)...${NC}"
    watch -n 10 "$0"
fi