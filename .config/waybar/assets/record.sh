#!/bin/bash
STATE_FILE="/tmp/waybarRecord"
PID_FILE="/tmp/waybarRecord.pid"
VIDEO_PATH_FILE="/tmp/waybarRecord_video_path"

if [ "$1" = "toggle" ]; then
    if [ -f "$STATE_FILE" ]; then
        # It's recording, so stop
        kill -SIGINT "$(cat "$PID_FILE")" 2>/dev/null
        rm -f "$PID_FILE" "$STATE_FILE"

        # Get the video filename that was saved when recording started
        if [ -f "$VIDEO_PATH_FILE" ]; then
            VIDEO_PATH=$(cat "$VIDEO_PATH_FILE")
            rm -f "$VIDEO_PATH_FILE"

            # Generate thumbnail
            THUMBNAIL_PATH="/tmp/$(basename "$VIDEO_PATH" .mp4).png"
            # Ensure the Videos directory exists before trying to generate a thumbnail
            mkdir -p "$(dirname "$VIDEO_PATH")"
            # Use ffmpeg to generate a thumbnail from the video
            # -ss 00:00:01: seek to 1 second into the video
            # -vframes 1: extract only one frame
            # -y: overwrite output file without asking
            ffmpeg -i "$VIDEO_PATH" -ss 00:00:01 -vframes 1 "$THUMBNAIL_PATH" -y &>/dev/null

            notify-send "Recording Stopped" "Video saved to $VIDEO_PATH" -u low -i "$THUMBNAIL_PATH"
            rm -f "$THUMBNAIL_PATH" # Clean up thumbnail
        else
            notify-send "Recording Stopped" "Video saved. Path not found." -u low
        fi
    else
        # Not recording, so start
        touch "$STATE_FILE"
        CURRENT_VIDEO_PATH="$(xdg-user-dir VIDEOS)/$(date +%Y%m%d_%H%M%S).mp4"
        echo "$CURRENT_VIDEO_PATH" > "$VIDEO_PATH_FILE" # Save video path for later use
        wf-recorder -a -f "$CURRENT_VIDEO_PATH" & # Start recording
        echo $! > "$PID_FILE"
        notify-send "Recording Started" "Capturing screen..." -u normal -i media-record
    fi
    pkill -SIGRTMIN+1 waybar
else
    # Show status in the bar
    if [ -f "$STATE_FILE" ]; then
        echo ""  # Icon when recording
    else
        echo "󰻂"   # Icon when not recording
    fi
fi
