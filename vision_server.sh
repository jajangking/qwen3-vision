#!/data/data/com.termux/files/usr/bin/bash
# VisionPsy-Nano server wrapper
# Usage: vision_server.sh [start|stop|status|web|cli|query IMAGE PROMPT]

LLAMA_DIR=~/visionpsy/build/bin
CUR=$(cat ~/visionpsy/models/current.txt 2>/dev/null || echo qwen3-vl-2b)
MODEL=~/visionpsy/models/$CUR/model.gguf
[ -f "$MODEL" ] || MODEL=~/visionpsy/models/$CUR/lm.gguf
MMPROJ=~/visionpsy/models/$CUR/mmproj.gguf
HOST=0.0.0.0
LAN_IP=$(ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
[ -z "$LAN_IP" ] && LAN_IP=$(ifconfig 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
PORT=8090
PID_FILE=~/visionpsy/.vision_server.pid
LOG_FILE=~/visionpsy/server.log

export LD_LIBRARY_PATH=$LLAMA_DIR:$LD_LIBRARY_PATH
export MTMD_NO_UPSCALE=1

start() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "already running (pid $(cat $PID_FILE))"
        return 0
    fi
    echo "starting vision server (model load ~5-30s)..."
    termux-wake-lock 2>/dev/null
    setsid bash -c "LD_LIBRARY_PATH=$LLAMA_DIR MTMD_NO_UPSCALE=1 MTMD_DISABLE_BATCH_SLICES=1 exec $LLAMA_DIR/llama-server \
        -m $MODEL \
        --mmproj $MMPROJ \
        -t 4 -c 4096 \
        -C 0xF0 \
        -fa auto \
        -b 2048 -ub 1024 \
        --no-warmup \
        --host $HOST --port $PORT" > "$LOG_FILE" 2>&1 &
    disown
    echo $! > "$PID_FILE"
    for i in $(seq 1 60); do
        if curl -s -m 2 http://$HOST:$PORT/health | grep -q '"ok"'; then
            echo "ready! (pid $(cat $PID_FILE))"
            return 0
        fi
        sleep 1
    done
    echo "timeout waiting for server; cek $LOG_FILE"
    return 1
}

stop() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        kill $(cat "$PID_FILE") 2>/dev/null
        rm -f "$PID_FILE"
        echo "stopped"
    else
        pkill -f llama-server 2>/dev/null && echo "stopped (lama)" || echo "not running"
    fi
}

status() {
    if curl -s -m 3 http://$HOST:$PORT/health | grep -q '"ok"'; then
        echo "running: $(curl -s http://$HOST:$PORT/health)"
    else
        echo "not running"
    fi
}

query() {
    local img="$1"
    local prompt="$2"
    if [ ! -f "$img" ]; then
        echo "error: image not found: $img"
        return 1
    fi
    if ! curl -s -m 3 http://$HOST:$PORT/health | grep -q '"ok"'; then
        start || return 1
    fi
    local tmp=$(mktemp)
    local maxpx=1024
    [ -f ~/visionpsy/models/$CUR/maxpx ] && maxpx=$(cat ~/visionpsy/models/$CUR/maxpx)
    local tmpimg=$(mktemp --suffix=.jpg)
    python3 ~/visionpsy/resize.py "$img" "$tmpimg" $maxpx 75 2>/dev/null || cp "$img" "$tmpimg"
    python3 - "$tmpimg" "$prompt" "$tmp" <<'EOF'
import sys, json, base64
img, prompt, out = sys.argv[1], sys.argv[2], sys.argv[3]
b64 = base64.b64encode(open(img, "rb").read()).decode()
json.dump({
    "model": "visionpsy",
    "messages": [{"role": "user", "content": [
        {"type": "text", "text": prompt},
        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}}]}],
    "max_tokens": 300,
}, open(out, "w"))
EOF
    curl -s -X POST http://$HOST:$PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d @"$tmp" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); c=d['choices'][0]['message']; print(c.get('content','') or c.get('reasoning_content',''))"
    rm -f "$tmp" "$tmpimg"
}

web() {
    local WEB_PORT=8091
    local OLD_PID=$(lsof -ti :$WEB_PORT 2>/dev/null)
    if [ -n "$OLD_PID" ]; then
        kill $OLD_PID 2>/dev/null; sleep 0.5
    fi
    local URL="http://${LAN_IP:-127.0.0.1}:$WEB_PORT"
    echo "web interface: $URL"
    cd ~/visionpsy/web && python3 -m http.server "$WEB_PORT" --bind "$HOST" &
    local WPID=$!
    echo "web server pid: $WPID"
    if command -v termux-open-url &>/dev/null; then
        termux-open-url "$URL"
    elif command -v termux-open &>/dev/null; then
        termux-open "$URL"
    fi
    wait $WPID
}

cli() {
    python3 ~/visionpsy/web/cli.py
}

case "${1:-status}" in
    start)  start ;;
    stop)   stop ;;
    status) status ;;
    web)    web ;;
    cli)    cli ;;
    query)  query "$2" "$3" ;;
    *)      echo "Usage: $0 {start|stop|status|web|cli|query IMAGE PROMPT}" ;;
esac