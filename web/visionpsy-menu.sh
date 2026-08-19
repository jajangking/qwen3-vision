#!/data/data/com.termux/files/usr/bin/bash
# VisionPsy launcher menu (ported from gemma4-vision llama.sh)
DIR=~/visionpsy
HOST=127.0.0.1
API_PORT=8090
WEB_PORT=8091
LAN_IP=$(ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
[ -z "$LAN_IP" ] && LAN_IP=$(ifconfig 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)

GREEN="\033[32m"; RED="\033[31m"; YELLOW="\033[33m"; CYAN="\033[36m"; BOLD="\033[1m"; DIM="\033[2m"; RESET="\033[0m"

health() { curl -s -m 3 "http://$HOST:$API_PORT/health" 2>/dev/null | grep -q '"ok"'; }

server_status() {
    if health; then echo -e "${GREEN}\u25cf Server online${RESET} ($HOST:$API_PORT)"; else echo -e "${RED}\u25cf Server offline${RESET}"; fi
}

start() {
    if health; then server_status; return 0; fi
    bash "$DIR/vision_server.sh" start
}

stop() {
    bash "$DIR/vision_server.sh" stop
}

web() {
    if health; then
        bash "$DIR/vision_server.sh" web
    else
        echo -e "${YELLOW}Server belum jalan. Pilih 1) Start server dulu.${RESET}"
        read -p "enter..." 
    fi
}

cli() {
    if health; then
        python3 "$DIR/web/cli.py"
    else
        echo -e "${YELLOW}Server belum jalan. Pilih 1) Start server dulu.${RESET}"
    fi
}

query() {
    if [ -z "$1" ]; then echo "Usage: $(basename $0) query <gambar> [prompt]"; return 1; fi
    bash "$DIR/vision_server.sh" query "$1" "${2:-Apa isi gambar ini? Jelaskan secara detail.}"
}

switch_model() {
    echo
    echo -e "${BOLD}Model yang tersedia:${RESET}"
    local opts=($(ls -d $DIR/models/*/ 2>/dev/null | xargs -n1 basename))
    local cur=$(cat $DIR/models/current.txt 2>/dev/null)
    local i=1
    for m in "${opts[@]}"; do
        if [ "$m" == "$cur" ]; then echo "  $i) $m ${GREEN}(aktif)${RESET}"; else echo "  $i) $m"; fi
        i=$((i+1))
    done
    echo "  0) batal"
    echo
    read -p "pilih model: " sel
    [ "$sel" -ge 1 ] 2>/dev/null && [ "$sel" -le ${#opts[@]} ] || return 0
    local m=${opts[$((sel-1))]}
    [ "$m" == "$cur" ] && { echo -e "${DIM}masih model yang sama${RESET}"; return 0; }
    echo "$m" > $DIR/models/current.txt
    echo -e "${YELLOW}restart server dengan model $m...${RESET}"
    bash "$DIR/vision_server.sh" stop 2>/dev/null
    sleep 1
    bash "$DIR/vision_server.sh" start || echo "$cur" > $DIR/models/current.txt
}

menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}Qwen3-VL-2B${RESET}"
        server_status
        echo -e "
  1) Start server
  2) Stop server
  3) Web UI  (http://${LAN_IP:-127.0.0.1}:$WEB_PORT)
  4) Chat CLI (streaming)
  5) Query 1 gambar langsung
  6) Status
  7) Ganti model  (${CYAN}$(cat $DIR/models/current.txt 2>/dev/null)${RESET})
  0) Keluar"
        echo
        read -p "pilih: " opt
        case "$opt" in
            1) start;               read -p "enter..." ;;
            2) stop;                read -p "enter..." ;;
            3) web ;;
            4) cli ;;
            5) read -p "path gambar: " img; query "$img" ;;
            6) server_status;       read -p "enter..." ;;
            7) switch_model;        read -p "enter..." ;;
            0|q) echo -e "${DIM}mematikan server...${RESET}"
                 stop
                 lsof -ti :$WEB_PORT 2>/dev/null | xargs -r kill
                 echo -e "${DIM}server dimatikan.${RESET}"
                 break ;;
            *) ;;
        esac
    done
}

case "${1:-menu}" in
    start)      start ;;
    stop)       stop ;;
    status)     server_status ;;
    web)        web ;;
    cli)        cli ;;
    query)      query "$2" "$3" ;;
    *)          menu ;;
esac