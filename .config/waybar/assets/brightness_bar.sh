#!/bin/bash

while true; do
    output=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)

    # Extrai número com regex (mais confiável)
    volume=$(echo "$output" | grep -oP '[0-9]+\.[0-9]+' | head -n1)

    # fallback caso falhe
    volume=${volume:-0}

    # converte pra %
    volume=$(printf "%.0f" "$(echo "$volume * 100" | bc -l)")

    # detecta mute
    if [[ "$output" == *"[MUTED]"* ]]; then
        muted="yes"
    else
        muted="no"
    fi

    FILLED=$((volume / 10))

    if [ "$volume" -gt 0 ] && [ "$FILLED" -eq 0 ]; then
        FILLED=1
    fi

    EMPTY=$((10 - FILLED))

    if [ "$muted" = "yes" ]; then
        BAR=" "
    else
        BAR=" "
    fi

    for ((i=0; i<FILLED; i++)); do BAR+="▮"; done
    for ((i=0; i<EMPTY; i++)); do BAR+="▯"; done

    echo "{\"text\": \"$BAR\", \"tooltip\": \"Volume: ${volume}%\", \"class\": \"custom-wireplumber\"}"

    sleep 0.5
done
