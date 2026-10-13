<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Deployment

Three shapes, from simplest to the one this was built on. All of them run
the same code; only the environment changes.

## 1. One machine (development, personal use)

Everything on localhost: the three model servers, smem, the database. The
[README quick start](../README.md#quick-start) is this shape, run by hand.

**Resources.** About 9 GB of RAM for the three servers at the settings in
`deploy/systemd/`, plus a little for smem. The LLM dominates. Any x86-64 or
ARM64 CPU that llama.cpp supports will work; a GPU build of llama.cpp makes
ingest and `ask` much faster, and needs no change to smem.

**One limitation to know about.** Each llama-server handles one request at a
time per slot. With one LLM slot, a search that needs the reranker is fine,
but an `ask` waits behind any extraction the background worker is running,
which can take about a minute on a CPU. If that matters, run the LLM with two
slots (`-c 6144 -np 2`, which roughly doubles its context memory). Or pause
dreaming with `SMEM_DREAMING=0` and ingest at quiet times.

### As systemd services

[`deploy/systemd/`](../deploy/systemd/) has four units:

| Unit | Runs |
|---|---|
| `smem-emb.service` | Embedder, `:8080`, memory-capped, restarted daily (it leaks slowly) |
| `smem-rrk.service` | Reranker, `:8081`, memory-capped (it leaks under load) |
| `smem-llm.service` | LLM, `:8082` |
| `smem-api.service` | API and console, `:8900`, on localhost |

```bash
# as root
useradd --system --home /var/lib/smem --shell /usr/sbin/nologin smem
git clone https://github.com/austingregoryus/smem-agent-memory /opt/smem-agent-memory
pip install numpy                            # or a venv; see smem-api.service
mkdir -p /var/lib/smem/models /etc/smem
# put the three GGUF files in /var/lib/smem/models (names: smem.env.example)
cp /opt/smem-agent-memory/deploy/smem.env.example /etc/smem/smem.env
chmod 600 /etc/smem/smem.env                 # edit: LLAMA_SERVER, model paths
cp /opt/smem-agent-memory/deploy/systemd/*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now smem-emb smem-rrk smem-llm smem-api
python3 -m smem health                       # from /opt/smem-agent-memory
```

The API unit is deliberately not ordered after the model servers. The console
comes up at once, and model calls retry until the servers are ready.

**On cgroup v1 hosts** (older kernels), replace `MemoryMax=` with
`MemoryLimit=` in the three model units. Otherwise the cap is accepted,
reported, and silently not applied ([GOTCHAS.md](GOTCHAS.md#memorymax-is-accepted-and-ignored-on-cgroup-v1)).

## 2. Several machines

Any machine that can run the three model servers can be a node: a spare
desktop, a mini PC, a NUC. Run the three model units on each, with
`LLAMA_HOST=0.0.0.0`, and list the nodes on the machine running smem:

```bash
SMEM_NODES=10.0.0.11,10.0.0.12
SMEM_BG_NODES=10.0.0.13
```

- **Every node runs all three models.** smem sends each request to the node
  with the least work in flight. Throughput scales close to linearly
  (2.96× on three nodes on the reference deployment), because no request
  depends on another node.
- **Do not split a model across machines** with llama.cpp's RPC backend.
  Measured on the reference deployment, it was 2.4× *slower* than one node.
- **`SMEM_BG_NODES` buys isolation.** With background work on its own nodes,
  searches and asks never queue behind an extraction. Without it, both lanes
  share every node.
- **All nodes use the same ports.** A node that is down is skipped for a few
  dispatches and retried, so a reboot costs capacity, not errors.

The model servers have no authentication. Keep them on a private network, or
behind a firewall that only admits the smem host.

## 3. The reference deployment: Intel VCA 2

smem was built for, and is still served by, two Intel Visual Compute
Accelerator 2 cards in a Proxmox host. Each card carries three Xeon
E3-1585L v5 nodes with about 15 GB of RAM each, reachable from the host as
`172.31.<n>.1` over a virtual network on the PCIe bus.

- **Interactive lane:** card 0, nodes `172.31.1-3.1`
- **Background lane:** card 1, nodes `172.31.4-6.1` (one of those nodes has
  since failed, and the pool works around it)
- **API and database:** on the host
- **Node telemetry:** on (`SMEM_NODE_PROBE=ssh`), so the console shows each
  node's temperature and memory
- **Lending:** a render farm borrows nodes through the pause file

[`deploy/vca2/`](../deploy/vca2/) has the scripts as they run there:

| File | Does |
|---|---|
| `services.sh` | Installs, starts, stops and checks the three model servers on every node over ssh, as units on each node's own disk. It also holds the sizing notes behind every flag. |
| `smem-api.service` | The host's API unit, with both lanes, the probe and the database path set explicitly |
| `install_host.sh` | Installs the two above so everything returns after a reboot |
| `swap_llm.sh` | Swaps the LLM on every node, for bake-offs |
| `measure_rss.sh` | Samples every server's resident memory under load |

The card itself (drivers, node images, the boot service, cooling) is
documented in [austingregoryus/vca2](https://github.com/austingregoryus/vca2).
Measured on a real reboot, the host was back in about 1.5 min, the nodes about
80 s after that, and the model servers 8 s after each node. The first search
after a reboot is slow while the models load.

## Security

- **Authentication is off by default**, and the API listens on localhost by
  default. Before binding to anything else (`--host 0.0.0.0`), set
  `SMEM_TOKEN`. There is one shared token; there are no per-user keys or
  accounts.
- **Browsers can reach a localhost API.** Every response allows any origin
  (CORS `*`), so with authentication off, a web page open in a browser on the
  same machine can call the API. Set `SMEM_TOKEN` if that browser visits
  sites you do not trust.
- **Containers isolate data, not users.** Anyone with the token can read any
  container.
- **URL ingest is SSRF-guarded.** Only http and https are allowed. Every
  resolved address must be public, and this is re-checked on each redirect,
  with 5 MB and 20 s limits. `SMEM_ALLOW_PRIVATE_URLS=1` lifts the address
  check; only set it when every token holder is trusted.
- **The console loads d3 from a CDN** (a pinned URL with subresource
  integrity) for the graph view. Everything else is served by smem itself.
- **The node probe runs ssh commands** on the nodes you list. It is off unless
  `SMEM_NODE_PROBE=ssh`.

## Backups

The database is one SQLite file (plus `-wal` and `-shm` while the server runs).
Back it up with SQLite's online backup, not a file copy:

```bash
sqlite3 /var/lib/smem/smem.db ".backup /backups/smem-$(date +%F).db"
```

Changing the embedder invalidates every stored vector. Stop the API, then run
`python -m smem reembed`. Text, memories, history and labels are kept.
