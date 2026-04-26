#!/bin/bash

while true; do
    # Get volume and mute status
    output=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)

    # Parse volume
    volume=$(awk -v out="$output" 'BEGIN { split(out, a, " "); printf "%.0f\n", a[2] * 100 }')

    # Check for MUTE tag (faster)
    if [[ "$output" == *"[MUTED]"* ]]; then
      muted="yes"
    else
      muted="no"
    fi

	FILLED=$((volume / 10))

	# garante que qualquer volume > 0 apareça como pelo menos 1 bloco
	if [ "$volume" -gt 0 ] && [ "$FILLED" -eq 0 ]; then
	    FILLED=1
	fi
	
    EMPTY=$((10 - FILLED))

    if [ "$muted" = "yes" ]; then
      BAR=" " # Mute icon
    else
      BAR=" " # Volume icon
    fi

    for ((i = 0; i < FILLED; i++)); do BAR+="▮"; done
    for ((i = 0; i < EMPTY; i++)); do BAR+="▯"; done

    # Output JSON for Waybar
    echo "{\"text\": \"$BAR\", \"tooltip\": \"Volume: ${volume}%\", \"class\": \"custom-wireplumber\"}"
done
