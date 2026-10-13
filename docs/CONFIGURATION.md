<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Configuration

smem is configured with environment variables and a few command-line flags.
There is no config file of its own. The systemd units read
`/etc/smem/smem.env`, and [`deploy/smem.env.example`](../deploy/smem.env.example)
lists every variable, commented out at its default.

The defaults describe **one machine**: smem and its three model servers on
localhost, the API bound to localhost, no authentication, and no node
telemetry.

## Server and CLI

| Variable | Default | Meaning |
|---|---|---|
| `SMEM_NODES` | `127.0.0.1` | Comma-separated hosts running the three model servers. Search, ask and direct writes use these (the *interactive lane*). |
| `SMEM_BG_NODES` | *(empty)* | Comma-separated hosts for the background worker (ingest and dreaming). Empty means it shares `SMEM_NODES`. If its own nodes are paused or failing, it falls back to `SMEM_NODES`. |
| `SMEM_PORT_EMB` | `8080` | Embedder port, the same on every node |
| `SMEM_PORT_RRK` | `8081` | Reranker port |
| `SMEM_PORT_LLM` | `8082` | LLM port |
| `SMEM_DB` | `~/.local/share/smem/smem.db` | SQLite database. The parent directory is created if missing. `--db` overrides it. |
| `SMEM_TOKEN` | *(unset)* | When set, every `/v*` route requires `Authorization: Bearer <token>`. The console asks for it on its Connect page. |
| `SMEM_DREAMING` | `1` | `0` starts the server with background typing and linking paused. It can be toggled at runtime with `POST /v1/dreaming`. |
| `SMEM_NODE_PROBE` | *(unset)* | `ssh` turns on per-node telemetry in the console: every 15 s, each node is asked over ssh for temperatures, memory and its model-server units. Unset means the probe thread never starts. |
| `NODE_PW` | *(unset)* | Password for the probe's ssh, via `sshpass`. Unset means key authentication (`ssh -o BatchMode=yes`). |
| `SMEM_PAUSE_FILE` | `/run/smem/paused.json` | File another service writes to borrow nodes temporarily: `{"nodes": [...], "until": <epoch seconds>}`. See [ARCHITECTURE.md](ARCHITECTURE.md#lanes). |
| `SMEM_ALLOW_PRIVATE_URLS` | *(unset)* | `1` lets URL ingest fetch private and LAN addresses. By default, every resolved address must be public. |

A node is a hostname or IP address. All nodes use the same three ports; a
`host:port` form per node is not supported.

### `python -m smem.server` flags

| Flag | Default | Meaning |
|---|---|---|
| `--host` | `127.0.0.1` | Listen address. Use `0.0.0.0` to serve the LAN, **and set `SMEM_TOKEN` when you do**: without it, anyone who can reach the port can read, change and delete every memory. |
| `--port` | `8900` | Listen port |
| `--db` | `$SMEM_DB` | SQLite database |
| `--container` | `default` | Container used when a request does not name one |
| `--no-telemetry` | off | Never start the node probe, even with `SMEM_NODE_PROBE=ssh` |
| `--no-worker` | off | Do not run the background worker: no queued ingest, no dreaming |

`smem-server` is installed as a shortcut for `python -m smem.server`.

### `python -m smem` (CLI) flags

`--db` (default `$SMEM_DB`) and `-c/--container` (default `default`) come
before the command. The CLI talks to the model servers and the database
directly; it does not need the API server to be running. See
[API.md](API.md#cli) for the commands.

## MCP bridge

Set these in the MCP client's configuration, not in `smem.env`.

| Variable | Default | Meaning |
|---|---|---|
| `SMEM_URL` | `http://127.0.0.1:8900` | API base URL |
| `SMEM_CONTAINER` | `claude` | The container this agent reads and writes |
| `SMEM_TOKEN` | *(empty)* | Bearer token; must match the server's |

## Model servers (`deploy/systemd/smem-*.service`)

| Variable | Default | Meaning |
|---|---|---|
| `LLAMA_SERVER` | `/usr/local/bin/llama-server` | llama.cpp server binary. The embedder needs build **b11476** or newer. |
| `LLAMA_HOST` | `127.0.0.1` | Address the model servers listen on. Use `0.0.0.0` when smem runs on another host. The model servers have no authentication of their own, so keep them off untrusted networks. |
| `LLAMA_THREADS` | `4` | CPU threads per server. Three run at once. |
| `SMEM_EMB_MODEL` | `/var/lib/smem/models/embeddinggemma-2-Q8_0.gguf` | Embedder GGUF |
| `SMEM_RRK_MODEL` | `/var/lib/smem/models/qwen3-reranker-0.6b-q8_0.gguf` | Reranker GGUF |
| `SMEM_LLM_MODEL` | `/var/lib/smem/models/gemma-4-E4B-it-Q4_K_M.gguf` | LLM GGUF |

The units also read `SMEM_PORT_EMB`, `SMEM_PORT_RRK` and `SMEM_PORT_LLM` for
their `--port`, so one env file keeps smem and its servers in agreement.

The llama-server flags themselves (context, batch and micro-batch sizes,
slots) are set in the unit files, with comments. Read
[GOTCHAS.md](GOTCHAS.md#memory-sizing-rss-follows-the-micro-batch-not-the-model)
before changing `-ub`.

## Constants in code

A few values are tied to the models and are deliberately not configurable.
Change them only together with the model:

| Constant | Where | Value | Tied to |
|---|---|---|---|
| `DIM` | `smem/models.py` | 768 | EmbeddingGemma 2's vector size |
| `QUERY_INSTRUCT`, `doc_text()` | `smem/models.py` | `task: search result \| query: `, `title: … \| text: …` | EmbeddingGemma 2's prompt format |
| `EMB_CHARS`, `RRK_CHARS` | `smem/models.py` | 5000, 1200 | The servers' context and micro-batch sizes |
| `MAX_CHARS` | `smem/chunk.py` | 1400 | Chunk size, and so the embedder's `-ub` |

## Reference deployment (`deploy/vca2/`)

The Intel VCA 2 scripts read a few variables of their own: `VCA_NODES` (the
node indexes to manage, `1 2 3 4 5 6`), `NODE_PW` (the nodes' root
password), `SMEM_UB` (reranker micro-batch), and `SMEM_CONTAINER` and
`SMEM_PORT` for the fallback API launch. See the top of
[`deploy/vca2/services.sh`](../deploy/vca2/services.sh).
