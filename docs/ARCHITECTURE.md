<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Architecture

smem is one Python process (the API, the console and a background worker)
in front of three llama.cpp servers. The Python side does no model work at
all: it stores rows in SQLite, keeps vectors as float32 blobs, and scores
them with a numpy dot product. Everything that needs a model is an HTTP call.

```
              ┌────────────────────────────────────────────┐
  agents ───► │  smem.server   :8900   HTTP API + console  │
  (MCP, HTTP) │  smem.engine           ingest / search /   │
  console ──► │                        reconcile / answer  │
              │  smem.store            SQLite + vectors    │
              │  worker thread         queue + dreaming    │
              └──────────────┬─────────────────────────────┘
                             │ HTTP, least-loaded dispatch
            ┌────────────────┼────────────────┐
            ▼                ▼                ▼
   ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
   │ node / host A  │ │ node / host B  │ │      ...       │
   │ :8080 embedder │ │ :8080 embedder │ │                │
   │ :8081 reranker │ │ :8081 reranker │ │                │
   │ :8082 LLM      │ │ :8082 LLM      │ │                │
   └────────────────┘ └────────────────┘ └────────────────┘
```

A node is anything running the three servers: the same machine as smem, a
second box on the LAN, or a node on a PCIe accelerator card. Each node holds
**a whole copy of every model**, and requests are distributed across nodes.
No model is ever split across machines.

That choice is what makes several small machines useful. On the reference
deployment, splitting one LLM across three nodes with llama.cpp's RPC
backend was 2.4× *slower* than a single node, because every token crosses
the network serially. Three independent workers were 2.96× *faster*, since
nothing they do depends on each other
([measurements](https://github.com/austingregoryus/vca2/blob/main/docs/BENCHMARK.md)).

## Data model

| Table | What it holds |
|---|---|
| `documents` | Source material as ingested: text or a fetched URL, with title and container |
| `chunks` | Heading-aware pieces of each document, with embeddings |
| `memories` | Atomic facts extracted from documents or stored directly, with embeddings, type, version and status |
| `memory_edges` | Relations between memories: updates (version chain) and extends |
| `decisions`, `labels`, `calibration` | Every judgement the background worker made, human labels, and the fitted calibration |

Every row carries a **container** tag, and every query filters on it, so
memories never leak between users, projects or agents.

Memories are **versioned, not overwritten**. When a new fact updates an old
one, the old row is kept with `is_latest = 0`, and the new row records
`version` and `supersedes`. Forgetting is a soft delete (`forgotten_at`), and
can be undone. You can mass-forget by natural-language query, which is a
dry run unless confirmed.

## Ingest

```
document
  → heading-aware chunks (~1400 chars, cut on paragraph boundaries)
  → embed, batched 16, fanned across the nodes          [parallel]
  → store chunks + vectors
  → LLM extracts atomic facts from ~3000-char groups    [parallel]
  → each fact reconciled against what is already known  [serial, by necessity]
  → stored as memories
```

Chunks are embedded with their heading path prepended (`FILE > Section >
Subsection`), which is a large retrieval win. The extractor receives the body
wrapped in `<document source="...">` tags instead, so it does not mistake the
heading path for a filename it has not been given (see
[GOTCHAS.md](GOTCHAS.md)).

**Reconciliation** compares each candidate fact with its nearest existing
memory, and a grammar-constrained judge answers one of three things:

- `DUPLICATE`: drop the candidate.
- `UPDATE`: store it as a new version of the old memory.
- `DISTINCT`: store it as a new memory.

This step is serial on purpose. Each fact must be compared against a store
the previous fact may just have changed, and running it in parallel would let
two contradictory facts both insert.

`POST /v3/documents` returns `202` with a job id at once. The worker thread
processes the queue, and `GET /v3/jobs` reports each job's phase. Documents
can be given inline, or as a public URL fetched server-side behind an SSRF
guard (http/https only, every resolved address must be public, re-checked on
each redirect, 5 MB and 20 s limits).

## Search and answers

```
question
  → embed with the model's query prompt
  → cosine over memories AND chunks → top 40            [numpy, sub-ms]
  → cross-encoder rerank the 40                         [parallel]
  → recency decay (memories only, off by default)
  → top k → compact numbered context
  → LLM answers with [n] citations                      (ask only)
```

There are two retrieval stages on purpose. The bi-encoder is cheap and
recall-oriented, but it scores a passage by the distance between two vectors.
The cross-encoder reads the query and the passage *together*, which is much
better for precision but costs a forward pass per pair. So the cosine stage
casts wide, and only its survivors get re-scored. The rerank pool is split
evenly between memories and chunks, because the embedder scores short
memories systematically higher than long chunks.

Skipping the rerank is a supported trade: on the reference deployment, recall
dropped from 15/15 to 12/15, and search latency fell from ~21 s to ~0.1 s.

**Decay applies to memories, not chunks.** A paragraph of a design document
is not less true for being six months old. A remembered fact about a system
that is being actively changed very often is. `half_life_days` weights
memories only.

## The background worker: queue, then dreaming

One thread with one database connection. It runs ingest jobs first. When the
queue is empty and the model servers have been quiet for 20 s (console
polling does not count), it **dreams**, which is Supermemory's word for
building the graph in the background:

1. **Typing.** Each memory becomes a FACT, PREFERENCE or EPISODE, nine per
   call.
2. **Extends links.** For each memory, the worker asks whether it adds
   detail to an older memory on the same subject (cosine ≥ the calibrated
   threshold, up to three candidates). The judge is deliberately
   conservative: it would rather miss a link than invent one.

Both judges answer **by probability, not by generating a word**. The options
are offered as letters, one token is generated, and each letter's probability
is read from the logprobs. That beat grammar-constrained answers in the
[decision bake-off](results/DECIDE.md). Every decision is logged. When a
human sets a type or confirms or rejects a link in the console, that becomes
a label. `smem/calibrate.py` re-fits how far to trust the model and where
each threshold sits, then re-applies the fit to every past decision.

The **profile** (`GET /v4/profile`) is built from the types:
- **static:** preferences, then facts, ranked by how connected they are;
- **dynamic:** episodes and updated memories from the last 14 days.

Jobs are held in memory, so a restart forgets the queue. Documents that were
already ingested are safe.

## Lanes

Interactive work (search, ask) and background work (ingest, dreaming) are
dispatched to two pools of nodes, `SMEM_NODES` and `SMEM_BG_NODES`. With
separate nodes, a search never queues behind a 60-second extraction. If the
background lane is down or lent out, it falls back to the interactive nodes.

**On a single machine both lanes share the same three servers.** Each
llama-server handles one request at a time unless it was started with
parallel slots, so a search can wait behind an extraction in progress. Run
the LLM with `-np 2`, or a second LLM instance on another port and host, if
that matters to you.

Other services can borrow nodes from smem by writing a pause file
(`SMEM_PAUSE_FILE`, default `/run/smem/paused.json`):

```json
{"nodes": ["10.0.0.5"], "until": 1767225600, "by": "renderfarm"}
```

`until` is mandatory, so a holder that crashes cannot keep a node forever.
`GET /v1/lanes` shows both lanes, paused nodes and in-flight counts.

## Dispatch

`smem/pool.py` sends each request to the node with the **least work in
flight**, with ties broken in rotation order. Plain round-robin was not
good enough: a request would often go to a node still busy with a 58-second
extraction while another sat idle. In-flight counts are kept per node, not
per port, because the three servers on one node share its cores.

A node that errors is parked for a few dispatches rather than removed. The
failure is usually a transient timeout under load, and evicting the node
would quietly drop its share of capacity for the rest of a long ingest.

## Concurrency and storage

- **One writer.** All writes go through one SQLite connection behind one
  lock, plus the worker's own connection. SQLite serialises the short write
  transactions. A failed refit or dream step rolls back, so it can never
  leave the write lock held.
- **Readers take no lock.** The console reads through its own read-only
  connection, so it stays responsive during a 60-second `ask` or an ingest.
- **Brute-force vector scan.** Every query scores every vector in the
  container. At tens of thousands of chunks that is still sub-millisecond and
  is dominated by the model calls. At millions it would need an index.
- **The embedding size is enforced.** A server that returns vectors of
  another size (an old embedder, a misconfigured node) is refused with an
  error, rather than stored next to vectors it cannot be compared with.
