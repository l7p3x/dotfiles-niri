#!/bin/bash

TEMP_FILE="/tmp/gammastep_current_temp"
MIN_TEMP=0
MAX_TEMP=4500
STEP=450
DEFAULT_TEMP=4500

# Inicializa o arquivo se não existir
[ ! -f "$TEMP_FILE" ] && echo $DEFAULT_TEMP > "$TEMP_FILE"

# Lê a temperatura atual
CURRENT=$(cat "$TEMP_FILE")

case "$1" in
    up)
        NEW=$(( CURRENT + STEP ))
        [ $NEW -gt $MAX_TEMP ] && NEW=$MAX_TEMP
        echo $NEW > "$TEMP_FILE"
        pkill gammastep 2>/dev/null
        nohup gammastep -O $NEW -P >/dev/null 2>&1 & disown
        ;;
    down)
        NEW=$(( CURRENT - STEP ))
        [ $NEW -lt $MIN_TEMP ] && NEW=$MIN_TEMP
        echo $NEW > "$TEMP_FILE"
        pkill gammastep 2>/dev/null
        nohup gammastep -O $NEW -P >/dev/null 2>&1 & disown
        ;;
esac

# Atualização visual (Barra de Progresso)
CURRENT=$(cat "$TEMP_FILE")
PERCENT=$(awk "BEGIN { printf \"%d\", ($CURRENT - $MIN_TEMP) / ($MAX_TEMP - $MIN_TEMP) * 100 }")
FILLED=$(( PERCENT / 10 ))
EMPTY=$(( 10 - FILLED ))
BAR=""
for ((i = 0; i < FILLED; i++)); do BAR+="▮"; done
for ((i = 0; i < EMPTY; i++)); do BAR+="▯"; done

echo "{\"text\": \" $BAR\", \"tooltip\": \"Temperature: ${CURRENT}K (${PERCENT}%)\", \"class\": \"custom-temperature\"}"
