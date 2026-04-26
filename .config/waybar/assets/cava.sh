#!/bin/bash

CONFIG="/tmp/waybar_cava.cfg"

# 1. Mata qualquer cava órfão da execução anterior
pkill -9 -x cava 2>/dev/null
sleep 0.4  # Delay crucial para o PipeWire liberar o áudio

# 2. Limpeza automática ao fechar o Waybar
trap 'pkill -P $$ cava 2>/dev/null; exit 0' SIGINT SIGTERM EXIT

# 3. Gera config se não existir
[ ! -f "$CONFIG" ] && cat > "$CONFIG" << 'EOF'
[general]
bars = 18
framerate = 30
autosens = 1
sensitivity = 100

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
EOF

# 4. Mapeamento 0-7 (8 caracteres para evitar o bug do "7")
bar="▁▂▃▄▅▆▇█"
dict="s/;//g;"
for i in $(seq 0 $((${#bar}-1))); do
    dict="${dict}s/$i/${bar:$i:1}/g;"
done

# 5. Loop infinito resiliente
while true; do
    stdbuf -oL cava -p "$CONFIG" 2>/dev/null | while IFS= read -r line; do
        echo "$line" | sed "$dict"
    done
    # Se o cava cair (ex: áudio desconectado), espera 0.5s e tenta de novo
    sleep 0.5
done
