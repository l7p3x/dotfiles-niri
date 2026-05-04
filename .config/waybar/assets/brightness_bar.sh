#!/bin/bash
BRIGHT_FILE="/tmp/brightness_current"
PID_FILE="/tmp/brightness.pid"
MIN_BRIGHT=0
MAX_BRIGHT=100
STEP=10
DEFAULT_BRIGHT=50

[ ! -f "$BRIGHT_FILE" ] && echo $DEFAULT_BRIGHT > "$BRIGHT_FILE"

CURRENT=$(cat "$BRIGHT_FILE")

case "$1" in
    up)
        NEW=$(( CURRENT + STEP ))
        [ $NEW -gt $MAX_BRIGHT ] && NEW=$MAX_BRIGHT
        echo $NEW > "$BRIGHT_FILE"
        ;;
    down)
        NEW=$(( CURRENT - STEP ))
        [ $NEW -lt $MIN_BRIGHT ] && NEW=$MIN_BRIGHT
        echo $NEW > "$BRIGHT_FILE"
        ;;
esac

# Mata o ddcutil anterior se ainda estiver rodando
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    kill "$OLD_PID" 2>/dev/null
fi

# Aplica o valor mais recente do arquivo (sempre atualizado)
( ddcutil setvcp 10 $(cat "$BRIGHT_FILE") >/dev/null 2>&1 ) &
echo $! > "$PID_FILE"

# Barra de progresso
CURRENT=$(cat "$BRIGHT_FILE")
FILLED=$(( CURRENT / 10 ))
EMPTY=$(( 10 - FILLED ))
BAR=""
for ((i = 0; i < FILLED; i++)); do BAR+="▮"; done
for ((i = 0; i < EMPTY; i++)); do BAR+="▯"; done
echo "{\"text\": \"󰃟 $BAR\", \"tooltip\": \"Brightness: ${CURRENT}%\", \"class\": \"custom-brightness\"}"
