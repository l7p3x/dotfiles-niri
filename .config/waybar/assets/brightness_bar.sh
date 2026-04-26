#!/bin/bash

BRIGHT_FILE="/tmp/brightness_current"
LOCK_FILE="/tmp/brightness.lock"
MIN_BRIGHT=0
MAX_BRIGHT=100
STEP=10
DEFAULT_BRIGHT=50

# Inicializa o arquivo se não existir
[ ! -f "$BRIGHT_FILE" ] && echo $DEFAULT_BRIGHT > "$BRIGHT_FILE"

# Lê o valor atual
CURRENT=$(cat "$BRIGHT_FILE")

case "$1" in
    up)
        NEW=$(( CURRENT + STEP ))
        [ $NEW -gt $MAX_BRIGHT ] && NEW=$MAX_BRIGHT
        echo $NEW > "$BRIGHT_FILE"
        # Atualiza o hardware em background
        ( flock -n 200 || exit 1; ddcutil setvcp 10 $NEW >/dev/null 2>&1 ) 200>"$LOCK_FILE" &
        ;;
    down)
        NEW=$(( CURRENT - STEP ))
        [ $NEW -lt $MIN_BRIGHT ] && NEW=$MIN_BRIGHT
        echo $NEW > "$BRIGHT_FILE"
        # Atualiza o hardware em background
        ( flock -n 200 || exit 1; ddcutil setvcp 10 $NEW >/dev/null 2>&1 ) 200>"$LOCK_FILE" &
        ;;
esac

# Atualização visual (Barra de Progresso)
CURRENT=$(cat "$BRIGHT_FILE")
PERCENT=$CURRENT # O brilho já é 0-100
FILLED=$(( PERCENT / 10 ))
EMPTY=$(( 10 - FILLED ))
BAR=""
for ((i = 0; i < FILLED; i++)); do BAR+="▮"; done
for ((i = 0; i < EMPTY; i++)); do BAR+="▯"; done

echo "{\"text\": \"󰃟 $BAR\", \"tooltip\": \"Brightness: ${CURRENT}%\", \"class\": \"custom-brightness\"}"
