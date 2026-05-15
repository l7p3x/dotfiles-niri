#!/bin/bash

STATE_FILE="/tmp/curr_brightness"
LOCK_FILE="/tmp/brightness.lock"
STEP=10
MIN=0
MAX=100

[ ! -f "$STATE_FILE" ] && echo 50 > "$STATE_FILE"
CURRENT=$(cat "$STATE_FILE")

case "$1" in
    up)
        NEW=$(( CURRENT + STEP ))
        [ $NEW -gt $MAX ] && NEW=$MAX
        ;;
    down)
        NEW=$(( CURRENT - STEP ))
        [ $NEW -lt $MIN ] && NEW=$MIN
        ;;
    *)
        NEW=$CURRENT
        ;;
esac

echo $NEW > "$STATE_FILE"

FILLED=$(( NEW / 10 ))
EMPTY=$(( 10 - FILLED ))
BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="▮"; done
for ((i=0; i<EMPTY; i++)); do BAR+="▯"; done
echo "{\"text\": \"󰃠 $BAR\", \"tooltip\": \"Brilho: ${NEW}%\"}"

(
  flock -n 9 || exit 0
  
  while true; do
    TARGET=$(cat "$STATE_FILE")
    
    LAST_SENT=$(cat "/tmp/last_sent_brightness" 2>/dev/null || echo -1)
    
    if [ "$TARGET" -eq "$LAST_SENT" ]; then
      break
    fi
    
    ddcutil setvcp 10 "$TARGET" --bus 1 --sleep-multiplier .5 >/dev/null 2>&1
    
    echo "$TARGET" > "/tmp/last_sent_brightness"
  done
) 9>"$LOCK_FILE" &
