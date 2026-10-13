<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# smem: self-hosted long-term memory for AI agents

smem gives agents a memory that lives on your own hardware. It ingests
documents and conversations, extracts **atomic facts** from them, keeps those
facts current as things change, and hands an agent back **a few hundred
tokens of relevant context** instead of forty pages. There's no API key, no
cloud model and no network egress: every model stage runs on llama.cpp
servers you control.

It follows the shape of [Supermemory](https://supermemory.ai)'s API and
concepts (container tags, memories versus documents, temporal truth,
forgetting, profiles): routes and field names follow Supermemory's, so
porting a client is mostly a base-URL change, though response shapes are
smem's own and only a subset of routes exists. *smem is an independent
project, not affiliated with Supermemory.*

> **Status:** working software, in daily use since September 2026 as the
> memory for the author's coding agents. One maintainer. The API is stable in
> practice but not yet versioned as a promise.

## What it does

- **Extracts facts, not just chunks.** An LLM turns each document into
  short, self-contained facts. Retrieval searches facts and source chunks
  together and returns the best of both, with citations.
- **Keeps facts current.** A new fact that updates an old one becomes a new
  *version*. The old one is kept, marked superseded, and can be shown as a
  timeline. Duplicates are dropped, and distinct facts are stored side by side.
- **Forgets on request.** Soft-delete one memory, or mass-forget everything
  matching a natural-language query (a dry run first). Every deletion is
  reversible.
- **Isolates by container.** Every row carries a container tag and every query
  filters on it. Give each project, user or agent its own space.
- **Builds a graph while idle ("dreaming").** In quiet periods it types each
  memory as a fact, preference or episode, and links memories that extend
  each other. It also builds a static and dynamic **profile** that an agent
  can load in one call at the start of a task.
- **Learns from correction.** Every background judgement is logged. When you
  confirm or reject one in the console, that label re-fits the thresholds
  and re-applies them to past decisions.
- **Comes with a console.** A web UI, served by the API itself with no build
  step, to browse, search, chat with, edit and graph a space.
- **Speaks MCP.** A single-file, standard-library-only MCP bridge plugs it into
  Claude Code, Claude Desktop or any MCP client.

## Why it is worth running

The point of agent memory is **context compression**: give a model twelve
one-line facts instead of the documents they came from, and it answers as well
for a fraction of the tokens. Measured over a 105,729-token documentation
corpus:

| Retrieval configuration | Recall@8 | Context returned |
|---|---:|---:|
| **Facts + chunks, reranked** | **15/15** | **1,232 tokens (98.83% less than the corpus)** |
| Chunks only, reranked | 15/15 | 2,845 tokens |
| Facts + chunks, no rerank | 12–13/15 | 417 tokens |

Facts reach the same recall as raw chunks with **2.3× fewer tokens**. The
recall figures depend on the models and the data. Latency depends on your
hardware: on the reference deployment (2016-era low-power Xeons, below), a
reranked search takes ~21 s and an unreranked one ~0.1 s. On a modern desktop
CPU or a GPU, expect a fraction of that.

Full measurements, including what was wrong before it was right, are in
[`docs/results/`](docs/results/).

## Built by measuring

The most useful thing in this repository may be the record of what failed
**silently**, each time with an HTTP 200 and a report of success:

- **A reasoning model returned empty strings.** A full ingest reported
  success with **zero facts extracted**, because the LLM spent its whole
  token budget thinking.
- **A free-text classifier returned an empty string** for exactly the
  cases it should have called duplicates, so every duplicate was stored.
- **The temporal-truth judge was wrong 50 times out of 73** on a real
  corpus while scoring 12/12 on its synthetic test set. Fixed to 19/22.
- **A memory cap that systemd reported as applied did nothing**, and a
  reranker leaked its way to 7 GB.

All of them, with their fixes, are in [`docs/GOTCHAS.md`](docs/GOTCHAS.md).

## Quick start

You need **Python 3.9+ with numpy**, **llama.cpp b11476 or newer**
(`llama-server`), and about **9 GB of free RAM** for the three models.

**1. Get the three models** (GGUF, about 6 GB in total):

| Role | Model | GGUF |
|---|---|---|
| Embedder | [EmbeddingGemma 2](https://huggingface.co/google/embeddinggemma-2) | [`embeddinggemma-2-Q8_0.gguf`](https://huggingface.co/ggml-org/embeddinggemma-2-GGUF), 0.31 GB |
| Reranker | [Qwen3-Reranker-0.6B](https://huggingface.co/Qwen/Qwen3-Reranker-0.6B) | [`qwen3-reranker-0.6b-q8_0.gguf`](https://huggingface.co/ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF), 0.64 GB |
| LLM | [gemma-4-E4B-it](https://huggingface.co/google/gemma-4-E4B-it) | [`gemma-4-E4B-it-Q4_K_M.gguf`](https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF), 4.98 GB |

```bash
HF=https://huggingface.co
curl -LO $HF/ggml-org/embeddinggemma-2-GGUF/resolve/main/embeddinggemma-2-Q8_0.gguf
curl -LO $HF/ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/resolve/main/qwen3-reranker-0.6b-q8_0.gguf
curl -LO $HF/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf
```

The prompts are written for these models specifically; see
[the models](docs/GOTCHAS.md#the-models) before swapping one.

**2. Start the model servers** (three terminals, or see
[`deploy/`](deploy/) for systemd units):

```bash
llama-server -m embeddinggemma-2-Q8_0.gguf --embedding -c 4096 -b 2048 -ub 2048 -np 2 --port 8080
llama-server -m qwen3-reranker-0.6b-q8_0.gguf --reranking -c 2048 -b 2048 -ub 768 --port 8081
llama-server -m gemma-4-E4B-it-Q4_K_M.gguf -c 3072 -np 1 --port 8082
```

**3. Install and start smem:**

```bash
git clone https://github.com/austingregoryus/smem-agent-memory
cd smem-agent-memory
pip install -e .
python -m smem health                  # all three servers should answer
python -m smem.server --port 8900      # API + console
```

Open **http://localhost:8900/** for the console.

**4. Use it.**

```bash
python -m smem -c notes ingest ./my-docs/          # documents → chunks → facts
python -m smem -c notes search "how is the cache invalidated"
python -m smem -c notes ask "what changed in the deploy process last week"
python -m smem -c notes remember "Staging now deploys from the release branch"
python -m smem -c notes forget "anything about the old CI"    # dry run first
```

Or over HTTP, in Supermemory's route shape:

```bash
curl -s localhost:8900/v4/search -d '{"q": "cache invalidation", "containerTag": "notes"}'
```

**5. Connect an agent** over MCP:

```bash
claude mcp add smem --scope user \
  -e SMEM_URL=http://localhost:8900 -e SMEM_CONTAINER=notes \
  -- python /path/to/smem-agent-memory/smem/connect/mcp_smem.py
```

The bridge tells the agent how to use it: load the profile once at the start
of a task, search before answering, and store one self-contained fact at a
time. The full tool list is in [`docs/API.md`](docs/API.md#mcp). An agent on
another machine can set itself up: point it at
`http://<host>:8900/connect/hermes.md`.

## Running on more than one machine

A node is anything running the three model servers. List several and smem
spreads work across them, always to the least-busy node. Each node holds
whole copies of the models; nothing is split across machines, which is why
it scales (2.96× on three nodes, where splitting one model across them was
2.4× *slower*).

```bash
SMEM_NODES=10.0.0.11,10.0.0.12 SMEM_BG_NODES=10.0.0.13 python -m smem.server
```

`SMEM_BG_NODES` gives background ingest and dreaming their own machines, so a
search never waits behind a 60-second extraction. On a single machine both
lanes share the same servers. See [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)
and [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md).

### The reference deployment

smem was built on, and is still served by, two **Intel VCA 2** cards: a
discontinued 2016 PCIe accelerator that is three complete Xeon computers on
one card, bought as e-waste. Five of those nodes run all three models each,
with interactive traffic on one card and background work on the other. The
hardware work behind it is in
[austingregoryus/vca2](https://github.com/austingregoryus/vca2), and the
deployment scripts are in [`deploy/vca2/`](deploy/vca2/).

## Documentation

| | |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | The pipeline, data model, dreaming, lanes and dispatch, and why each piece is the way it is |
| [CONSOLE.md](docs/CONSOLE.md) | The web console, view by view |
| [API.md](docs/API.md) | Every HTTP route, the MCP tools and the CLI |
| [CONFIGURATION.md](docs/CONFIGURATION.md) | Every environment variable and flag |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | One machine, several machines, systemd, authentication |
| [GOTCHAS.md](docs/GOTCHAS.md) | The models, and every silent failure found so far |
| [results/](docs/results/) | The measurements behind the design decisions |

## Limits, honestly

- **Partial Supermemory parity.** smem has spaces, profiles, update and
  extends relations, background dreaming, URL ingest and a console. It has no
  *derives* relations (inferred facts), no profile buckets, no entity
  extraction, no connectors (Drive, Notion, …), and no multi-user accounts.
  Authentication is one optional shared bearer token.
- **Extends coverage is low by design.** The judge would rather miss a link
  than invent one, and finds roughly two in five.
- **Ingest is a batch job.** Extraction is one LLM call per ~3,000
  characters, and it is prefill-bound. On the reference hardware a 22-file,
  105k-token corpus took about an hour. A GPU changes this completely.
- **Reconciliation is serial**, and only checks the single nearest existing
  memory.
- **Brute-force vector scan.** That is fine to tens of thousands of chunks.
  At millions, it would need an index.
- **One writer.** SQLite, one write connection.
- **The ingest queue is in memory.** A restart forgets queued jobs, but
  documents already ingested are safe.

## Repository layout

| Path | What |
|---|---|
| [`smem/`](smem/) | The package: engine, store, models, dispatch, server, CLI, console (`ui/`), MCP bridge and agent setup files (`connect/`) |
| [`tests/`](tests/) | Offline tests: chunker, store, calibration. No model servers needed. |
| [`eval/`](eval/) | Measurement harnesses (retrieval, temporal truth, bake-offs) and their recorded data |
| [`deploy/`](deploy/) | systemd units and an example environment file; [`deploy/vca2/`](deploy/vca2/) is the reference deployment |
| [`docs/`](docs/) | Architecture, API, configuration, deployment, gotchas, results |

```bash
python tests/test_smem.py      # offline, a few seconds
```

## Licence

Code is **MIT** ([`LICENSE`](LICENSE)). Documentation and the measurement data
in `eval/data/` are **CC BY 4.0** ([`LICENSES/CC-BY-4.0.txt`](LICENSES/CC-BY-4.0.txt)).
Built with substantial AI assistance (Claude), directed and checked by the
author. If you use it in research, [`CITATION.cff`](CITATION.cff) has the
citation.
