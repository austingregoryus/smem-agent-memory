#!/bin/sh
# SPDX-License-Identifier: MIT
# Run bench_decide.py against small models on one node, one at a time, on a
# temporary port (8083) next to production. Each server is a transient
# systemd unit, stopped afterwards; production units are not touched.
#
#   NODE=172.31.2.1 sh eval/bench_decide_small.sh
#
# VCA-SPECIFIC HARNESS: written for an Intel VCA 2 node (deploy/vca2/): the
# node IP, /root model paths and the VCA default password are that setup's.
# Results go to eval/data/decide/.
NODE="${NODE:-172.31.2.1}"
NODE_PW="${NODE_PW:-vista1}"
n(){ sshpass -p "$NODE_PW" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$NODE" "$1"; }
cd "$(dirname "$0")" || exit 1          # eval/: bench_decide.py is here
mkdir -p data/decide
for spec in qwen35-08b:qwen35-08b-q8.gguf qwen35-2b:qwen35-2b-q4km.gguf llama32-1b:llama32-1b.gguf; do
    name=${spec%%:*}; file=${spec#*:}
    n "systemctl stop bench-llm 2>/dev/null; systemctl reset-failed bench-llm 2>/dev/null;
       systemd-run --unit=bench-llm --property=MemoryLimit=3G /root/bin/llama-server \
         -m /root/$file -t 8 -c 2048 -np 1 --host 0.0.0.0 --port 8083"
    ok=0
    for _ in $(seq 60); do
        if curl -s -m 2 "http://$NODE:8083/health" | grep -q ok; then ok=1; break; fi
        sleep 2
    done
    if [ $ok = 1 ]; then
        python3 bench_decide.py --node "$NODE" --llm-port 8083 --name "$name" \
            --methods grammar,letters1,letters --out "data/decide/$name.json" 2> "data/decide/$name.err"
        echo "$name done"
    else
        echo "$name: server did not come up"; n "journalctl -u bench-llm -n 20 --no-pager"
    fi
    n "systemctl stop bench-llm"
done
