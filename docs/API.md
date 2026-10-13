<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# API reference

Everything smem exposes: the HTTP API (`smem/server.py`), the MCP bridge
(`smem/connect/mcp_smem.py`) and the command line (`smem/cli.py`). This page
is derived from that code; where a docstring elsewhere disagrees, the code is
what is described here.

## Conventions

| Topic | Behaviour |
|---|---|
| Base URL | `http://localhost:8900` (the server binds `127.0.0.1:8900` by default; `--host`, `--port`) |
| Bodies | JSON. Send `Content-Length`; chunked request bodies are not read. The `Content-Type` header is ignored. A body that is not valid JSON, or not a JSON object, is answered `400` |
| Responses | JSON (`application/json`), except `/` (HTML) and `/connect/*` (text). Every response carries `Access-Control-Allow-Origin: *`; `OPTIONS` answers 204 with CORS headers and is never authenticated |
| Container | The isolated memory space, called `containerTag` as in Supermemory. In POST bodies it is `containerTag`; in GET requests it is the query parameter `containerTag`. When omitted, the server uses its `--container` flag, which defaults to **`default`**. (The MCP bridge and the CLI choose their own defaults, see below.) Containers need no creation step: they exist once something is written to them |
| Auth | If the server process has `SMEM_TOKEN` set, every route whose path starts with `/v` needs `Authorization: Bearer <token>`; otherwise the response is `401 {"error": "missing or wrong bearer token"}`. Left open: `/health`, `/`, `/index.html`, `/connect`, `/connect/*` and `OPTIONS`. With no `SMEM_TOKEN`, nothing is authenticated. There is one shared token, no per-user keys |
| Errors | `{"error": "<message>"}` with a status code: 400 missing field or bad value, 401 token, 404 unknown id or route (`"not found"`, `"no such route"`), 409 stale `PATCH`, 422 failed ingest with `wait`, 500 any uncaught exception (`"<ExceptionType>: <message>"`; a non-numeric `limit` is a 500, not a 400) |
| Prefixes | `/v3/*` and `/v4/*` follow the shape of Supermemory's routes. `/v1/*` are smem's own (ask, containers, stats, graph, worker, telemetry) |
| Compatibility | The route names, `containerTag`, `q`, `limit`, `customId` and the 202-then-poll document flow follow Supermemory, so porting a client is mostly a base-URL change. Responses are **not** byte-compatible: field names and nesting were chosen by smem (for example search returns `results[]` with `vectorScore`/`rerankScore`/`decay`, and `timing`), only a subset of Supermemory's routes exists, and smem adds routes of its own. Treat the shapes below as the contract, not Supermemory's documentation |

Ids are prefixed: `doc_`, `mem_`, `chk_`, `job_`.

## Route summary

### Documents and jobs

| Method | Path | Purpose |
|---|---|---|
| POST | `/v3/documents` | Ingest text or a URL; queued as a job (202) |
| GET | `/v3/jobs` | Ingest jobs and their status (newest 50, in memory) |
| GET | `/v3/documents` | List documents in a container |
| GET | `/v3/documents/{id}` | One document with its content and memories |
| DELETE | `/v3/documents/{id}` | Hard delete the document, its chunks and its memories |

### Memories

| Method | Path | Purpose |
|---|---|---|
| POST | `/v3/memories` | Store one fact (reconciled against existing memories) |
| GET | `/v3/memories` | Page through memories, with filters |
| GET | `/v3/memories/{id}/history` | Every version of a memory, plus its relations |
| PATCH | `/v3/memories/{id}` | Replace the text: stores a new version |
| DELETE | `/v3/memories/{id}` | Forget (soft delete, reversible) |
| POST | `/v3/memories/{id}/restore` | Undo a forget |
| POST | `/v3/memories/forget` | Forget everything matching a query (dry run unless `confirm`) |
| POST | `/v3/memories/{id}/type` | Set a memory's type by hand (`fact`, `preference`, `episode`) |
| POST | `/v1/relations/feedback` | Label a judged memory pair; corrects the edge |

### Search and answers

| Method | Path | Purpose |
|---|---|---|
| POST | `/v4/search` | Ranked facts and document passages |
| POST | `/v1/ask` | Written, cited answer from a local model (slow) |

### Profile and graph

| Method | Path | Purpose |
|---|---|---|
| GET | `/v4/profile` | Static and dynamic profile of a container |
| GET | `/v1/graph` | Documents, memories and their relations, for the console |

### Spaces and stats

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/containers` | Containers with document and live-memory counts |
| GET | `/v1/stats` | Counts for one container |
| GET | `/v1/overview` | Stats, types, document list, nodes and activity in one call |

### Background worker and calibration

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/dreaming` | Worker state, queue length, backlog |
| POST | `/v1/dreaming` | Pause or resume the worker |
| GET | `/v1/calibration` | Fitted temperatures and thresholds, label counts |
| POST | `/v1/calibration/fit` | Refit now from the labels collected so far |

### Operations

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness and per-node model-server status (no auth) |
| GET | `/v1/nodes` | Node telemetry (needs `SMEM_NODE_PROBE=ssh`) |
| GET | `/v1/lanes` | Interactive and background nodes, paused nodes, in-flight calls |
| GET | `/v1/activity` | Request log and per-route latency |

### Console and setup files

| Method | Path | Purpose |
|---|---|---|
| GET | `/`, `/index.html` | Web console (no auth) |
| GET | `/connect`, `/connect/` | Plain-text list of setup files (no auth) |
| GET | `/connect/{name}` | `mcp_smem.py` or one of the `*.md` files in `smem/connect/` (no auth) |

## Documents and jobs

### POST /v3/documents

Queue a document for ingest. The work (fetch, chunk, embed, extract facts,
reconcile) runs in the single background worker, so a document takes roughly a
minute per 3,000 characters when facts are extracted.

| Field | Type | Default | Notes |
|---|---|---|---|
| `content` | string | | The text. One of `content` or `url` is required (400 `content or url required`) |
| `url` | string | | http(s) page to fetch (5 MiB cap). If both are given, `url` wins at run time |
| `containerTag` | string | server default | |
| `title` | string | the page title for a `url`, else the URL, else `Untitled` | |
| `customId` | string | the `url`, if any | Re-ingesting the same `customId` in a container replaces the earlier document and its memories. Without a `customId` (text with no id) every call adds a new document |
| `metadata` | object | | Stored on the document |
| `extract` | boolean | `true` | `false` = chunk and embed only: fast, no facts |
| `wait` | boolean | `false` | Block until the job finishes |

| Result | Status | Body |
|---|---|---|
| Queued | **202** | the job: `id` (`job_...`), `container`, `title`, `url`, `status` (`queued`), `phase`, `createdAt`, `startedAt`, `finishedAt`, `result`, `error`, `chars` |
| `wait` and succeeded | 201 | the job fields merged with the ingest result: `doc_id`, `chunks`, `memories`, `embed_s`, `extract_s`, `total_s`, `elapsed` |
| `wait` and failed | 422 | the job fields with `status: "failed"` and `error` |

Job `status` is `queued`, `processing`, `done` or `failed`; `phase` is a
human-readable step. Jobs are held in memory (newest 200) and are lost on
restart; documents already ingested are safe. With `--no-worker` nothing
consumes the queue, so `wait: true` never returns.

```sh
# by content
curl -s localhost:8900/v3/documents -d '{
  "content": "# Cache notes\n\nInvalidate on write, not on read.",
  "title": "cache-notes", "customId": "cache-notes", "containerTag": "notes"}'
# -> 202 {"id": "job_3f0c...", "status": "queued", ...}

# by url
curl -s localhost:8900/v3/documents -d '{
  "url": "https://example.com/post", "containerTag": "notes"}'
```

### GET /v3/jobs

Query: `containerTag` (optional; with it, only that container's jobs, without it
all). Returns `{"jobs": [...]}`, newest first, at most 50, each in the job shape
above.

### GET /v3/documents

Query: `containerTag`. Returns `{"documents": [{id, title, customId, chars,
chunks, facts, superseded, createdAt}]}`.

### GET /v3/documents/{id}

Returns `id`, `title`, `content`, `customId`, `container`, `source`,
`createdAt`, `metadata`, and `memories[]` (up to 500, all statuses, in the
memory shape below). 404 `not found`. The container is not checked.

### DELETE /v3/documents/{id}

Hard delete of the document, its chunks and every memory extracted from it.
Not reversible. Returns `{"id", "deleted": true, "memoriesDeleted": n}`; 404 if
unknown.

## Memories

The **memory shape** used in lists, profiles and history:

| Field | Meaning |
|---|---|
| `id`, `content`, `version` | |
| `isLatest` | `false` for a superseded version |
| `forgotten` | soft-deleted |
| `supersedes`, `supersededBy` | version chain ids (or `null`) |
| `createdAt` | epoch seconds |
| `documentId`, `documentTitle` | source document, if extracted from one |
| `type`, `typeConf` | `fact`, `preference` or `episode`, and the classifier's confidence; `null` until the worker has typed it |
| `degree` | relation count; present only in profile results |

### POST /v3/memories

Body: `content` (required, 400 otherwise), `containerTag`. The fact is embedded
and compared with the nearest existing memory: a restatement is dropped, a
contradiction becomes a new version and the old one is kept as history.
Returns **201** `{"stored": n, "duplicate": n == 0}`.

```sh
curl -s localhost:8900/v3/memories -d '{
  "content": "The staging database is Postgres 16.", "containerTag": "notes"}'
# -> 201 {"stored": 1, "duplicate": false}
```

### GET /v3/memories

| Query | Default | Notes |
|---|---|---|
| `containerTag` | server default | |
| `status` | `live` | `live`, `superseded`, `forgotten`, `all`. Any other value applies no status filter (same as `all`). `history=1` forces `all` |
| `q` | | Case-insensitive substring match on content (SQL `LIKE`; not semantic) |
| `docId` | | Only memories from this document |
| `type` | | `fact`, `preference`, `episode`, or `unclassified` |
| `limit` | 50 | capped at 500 |
| `offset` | 0 | |

Returns `{"total": n, "memories": [...]}`, newest first.

### GET /v3/memories/{id}/history

Returns `{"versions": [...], "relations": [...]}`. `versions` are in the memory
shape (with `documentTitle` and `supersededBy`). `relations` entries:
`kind` (`extends`, `duplicate`, ...), `direction`, `src`, `dst`, `id` and
`content` of the other memory, `score`, `conf`, `isLatest`. An unknown id
returns 200 with an empty `versions`, not 404.

### PATCH /v3/memories/{id}

Body: `content` (required, non-blank; 400). Stores a new version that
supersedes `{id}`; the old text stays in history. The new text is not
reconciled against other memories and is not re-typed until the worker gets to
it. Returns 200 `{"id": <new id>, "supersedes": <old id>, "version": n}`.

| Status | When |
|---|---|
| 404 | no such memory |
| 409 | the memory is already superseded or forgotten: `only the current version of a live memory can be updated`. Re-read the latest id (via history) and retry |

```sh
curl -s -X PATCH localhost:8900/v3/memories/mem_0a1b2c3d4e5f -d '{
  "content": "The staging database is Postgres 17."}'
```

### DELETE /v3/memories/{id}

Soft delete: sets `forgotten_at`, the row and its history remain. Returns
`{"id", "forgotten": true, "reversible": true}`; 404 if unknown. Forgotten
memories no longer appear in search or the default list.

### POST /v3/memories/{id}/restore

Clears the forget. Returns `{"id", "forgotten": false}`; 404 if unknown.
Restoring a memory that was not forgotten is a no-op that still returns 200.

### POST /v3/memories/forget

Forget by natural-language query. Matching is a vector pre-filter followed by
the cross-encoder, so it needs the embedder and reranker up.

| Field | Default | Notes |
|---|---|---|
| `q` | | required (400). `query` is accepted as an alias |
| `containerTag` | server default | |
| `threshold` | 0.60 | minimum rerank score |
| `confirm` | falsy | **Without it nothing is changed**: dry run |

Returns `{"matched": [{"id", "content", "score"}], "forgotten": false}` for a
dry run, and the same with `"forgotten": true` when `confirm` is truthy. Each
forgotten memory can be restored individually.

```sh
curl -s localhost:8900/v3/memories/forget -d '{"q": "the old cooler", "containerTag": "notes"}'
curl -s localhost:8900/v3/memories/forget -d '{"q": "the old cooler", "containerTag": "notes", "confirm": true}'
```

### POST /v3/memories/{id}/type

Not in the server's module docstring. Body: `type` (`fact`, `preference` or
`episode`, case-insensitive; 400 otherwise). Sets the type with confidence 1.0
and records a `user` label that feeds calibration. Returns
`{"id", "type", "labelled": true}`; 404 if unknown.

### POST /v1/relations/feedback

Not in the module docstring. Body: `src`, `dst` (memory ids) and `label`
(`EXTENDS`, `DUPLICATE`, `UPDATE`, `UNRELATED`; case-insensitive). The pair is
ordered newer to older automatically, any existing edge between them is
replaced (for `EXTENDS`/`DUPLICATE`) or removed, and the label is stored for
calibration. Returns `{"src", "dst", "label"}`; 400 bad label, 404 unknown id.

## Search and answers

### POST /v4/search

| Field | Default | Notes |
|---|---|---|
| `q` | | required (400 `q (the query text) is required`). `query` is accepted as an alias |
| `containerTag` | server default | |
| `limit` | 8 | results returned |
| `rerank` | `false` | `true` adds a cross-encoder pass over the top 40 candidates |
| `halfLifeDays` | none | recency decay for **memories** only (chunks are never decayed): score is multiplied by `0.5^(age/halfLife)` |

Returns:

```json
{"results": [{"id": "mem_...", "type": "memory", "content": "...", "heading": null,
              "score": 0.81, "vectorScore": 0.81, "rerankScore": 0.81,
              "decay": 1.0, "documentId": "doc_...", "title": "cache-notes"}],
 "timing": {"vectorMs": 92.1, "rerankMs": 0.0}}
```

`type` is `memory` (an extracted or stored fact) or `chunk` (a passage of a
document). Without `rerank`, `rerankScore` simply equals `vectorScore` and
`score` is that value times `decay`. `timing` comes from the first hit, so it
is `0`/`0` when there are no results. Search is not paged.

```sh
curl -s localhost:8900/v4/search -d '{"q": "cache invalidation", "containerTag": "notes", "limit": 5}'
curl -s localhost:8900/v4/search -d '{"q": "cache invalidation", "containerTag": "notes", "rerank": true}'
```

### POST /v1/ask

Body: `q` (required; `query` alias), `containerTag`, `limit` (8),
`halfLifeDays`. There is no `rerank` field: **ask always reranks**, then
passes the hits to the local LLM (max 400 tokens, temperature 0.2).

Returns `{"answer", "contextTokens", "sources": [<search result>...],
"timing": {"retrieveS", "generateS", "totalS"}}`. If nothing matches, the
answer is `Nothing in this container matches that.` and `sources` is empty
(`timing` values are then `null`).

```sh
curl -s localhost:8900/v1/ask -d '{"q": "How do we invalidate the cache?", "containerTag": "notes"}'
```

## Profile and graph

### GET /v4/profile

Query: `containerTag`, `static` (max static items, 12), `dynamic` (max dynamic
items, 10).

| Field | Meaning |
|---|---|
| `container` | |
| `static` | Preferences first (newest first), then facts ranked by how many `extends` relations they have; memory shape plus `degree`. Memories whose type confidence is below the threshold are left out |
| `dynamic` | Episodes, plus facts that superseded an older version in the last 14 days |
| `types` | Live memory counts by type, with `unclassified` |
| `unclassified` | Memories the worker has not typed yet |
| `uncertain` | Live memories below the type-confidence threshold |
| `typeThreshold` | The threshold in force |

The profile is built from what the background worker has typed and linked, so
a fresh container returns it mostly empty until the worker catches up.

```sh
curl -s "localhost:8900/v4/profile?containerTag=notes"
```

### GET /v1/graph

Query: `containerTag`, `sim` (0; memory-to-memory `similar` edges above this
cosine, off at 0), `docSim` (0.90; document-to-document edges), `history` (`1`;
include superseded versions), `forgotten` (`0`; include forgotten ones; `1` or
`true`). Returns `nodes` (`document`, `memory`, `superseded`, `forgotten`),
`edges` (`{s, t, kind, w?}` with kinds `source`, `updates`, `extends`,
`docsim`, `similar`), `counts`, `edgeCounts`, `docSim`.

## Spaces and stats

| Route | Returns |
|---|---|
| `GET /v1/containers` | `{"containers": [{"name", "documents", "memories"}], "default": "<server default>"}`. `memories` counts live ones |
| `GET /v1/stats?containerTag=` | `documents`, `chunks`, `memories_live`, `memories_superseded`, `memories_forgotten`, `corpus_chars` |
| `GET /v1/overview?containerTag=` | `container`, `stats`, `types`, `extends` (edge count), `created` (hourly series), `documents[]`, `nodes` (as `/v1/nodes`), `activity` (as `/v1/activity`) |

## Background worker and calibration

One thread processes ingest jobs first and, when no model request has arrived
for `idleAfterS` (20 s), works through "dreaming": typing each memory as
fact/preference/episode and finding `extends` links. Console polling (GETs)
does not count as activity. `SMEM_DREAMING=0` starts it paused; `--no-worker`
never starts it.

### GET /v1/dreaming

Returns `enabled`, `state`, `since`, `last` (last dreaming step), `done`
(counters: `documents`, `classified`, `checked`, `extends`), `queue` (jobs
queued or processing), `backlog` (memories still to type or check),
`lastFit`, `idleAfterS`.

### POST /v1/dreaming

Body `{"enabled": true|false}` (missing = `true`). Returns `{"enabled": ...}`.
Ingest jobs still run while dreaming is paused. The setting is not persisted.

### GET /v1/calibration

Returns `kinds.type` and `kinds.extends` (each: `temperature`, `threshold`,
`fitted`, `fittedAt`, `stats`, `labelled`, `minLabels`), `labels`, `decisions`
(logged judgements per kind) and `targets`.

### POST /v1/calibration/fit

No body. Refits both kinds that have enough labels and re-applies the result to
past decisions; returns `{"type": ..., "extends": ..., "reapplied": ...}`
where a kind without enough labels reads `"not enough labels yet"`. The worker
also refits automatically after every 5 new labels.

## Operations

| Route | Returns |
|---|---|
| `GET /health` | `{"ok": true, "auth": <bool>, "nodes": {"<host>": ["emb","rrk","llm"]}}`. A server that cannot be reached shows as `EMB-DOWN`, `RRK-DOWN` or `LLM-DOWN` (5 s timeout each). `ok` is `true` whenever the API itself is up, even with every model server down, so check `nodes` too. No auth |
| `GET /v1/nodes` | `{"probe", "updated", "card", "nodes": [...]}`. Empty and `probe: false` unless `SMEM_NODE_PROBE=ssh`; then it is refreshed every 15 s over ssh (temperatures, memory, load, `sm-emb`/`sm-rrk`/`sm-llm` unit state, lane, paused, in-flight) |
| `GET /v1/lanes` | `interactive` and `background` node lists, `shared` (true when there is no separate background lane), `paused` (nodes lent out through `SMEM_PAUSE_FILE`), `inflight` per node |
| `GET /v1/activity` | `uptimeS`, `total`, `routes[]` (`route`, `count`, `errors`, `p50`, `p95` in ms), `perMinute` (60 buckets), `recent` (last 60 requests). Covers the last 5,000 `/v*` requests since start |

## Console and setup files

`GET /` serves the single-page console from `smem/ui/index.html`; it asks for
the token when auth is on.

`GET /connect/` returns a plain-text list of the files an agent on another
machine can fetch: `mcp_smem.py` (served as `text/x-python`) and every `*.md`
in `smem/connect/` (`hermes.md`, `soul-snippet.md`; served as
`text/markdown`). Only those names are served; anything else is 404
`no such setup file`.

An agent sets itself up by following `hermes.md`: (1) `curl /health`;
(2) download `/connect/mcp_smem.py` to a local path and syntax-check it;
(3) register it as a stdio MCP server with `SMEM_URL` and its own
`SMEM_CONTAINER`, with a client timeout of at least 180 s because
`ask_memory` can take 40-120 s; (4) append `soul-snippet.md` (also at
`/connect/soul-snippet.md`) to its standing instructions; (5) test with
`get_profile`, `add_memory` and `search_memories`. `hermes.md` is written for
Hermes Agent and names that agent's config files and the `hermes` container;
other agents apply the same steps to their own configuration. When the server
sets `SMEM_TOKEN`, the bridge needs the same `SMEM_TOKEN` in its environment.

## MCP

`mcp_smem.py` is a stdio MCP server (newline-delimited JSON-RPC 2.0). It is
standard library only (Python 3.8+, nothing to install), and a running server
serves it at `/connect/mcp_smem.py`. It forwards each tool call to the HTTP
API; it never talks to the model servers itself.

```sh
claude mcp add smem --scope user -e SMEM_URL=http://localhost:8900 -e SMEM_CONTAINER=notes -- python /path/to/smem-agent-memory/smem/connect/mcp_smem.py
```

Any other MCP client, in the usual `mcpServers` form (Claude Desktop and
others):

```json
{
  "mcpServers": {
    "smem": {
      "command": "python",
      "args": ["/path/to/smem-agent-memory/smem/connect/mcp_smem.py"],
      "env": {
        "SMEM_URL": "http://localhost:8900",
        "SMEM_CONTAINER": "notes"
      }
    }
  }
}
```

| Variable | Default | Meaning |
|---|---|---|
| `SMEM_URL` | `http://127.0.0.1:8900` | API base URL |
| `SMEM_CONTAINER` | **`claude`** | Container used when a tool call gives no `container`. Note this differs from the server's own default (`default`) |
| `SMEM_TOKEN` | empty | Sent as `Authorization: Bearer` when set |

### Tools

Every tool except `memory_history`, `forget_memory`, `restore_memory` and
`list_containers` also takes an optional `container` (string).

| Tool | Arguments (default) | Calls |
|---|---|---|
| `search_memories` | `query` (required), `limit` (8), `rerank` (false) | `POST /v4/search` |
| `add_memory` | `content` (required) | `POST /v3/memories` |
| `ask_memory` | `question` (required) | `POST /v1/ask` |
| `list_memories` | `filter` (substring), `status` (`live`; or `superseded`, `forgotten`, `all`), `limit` (20) | `GET /v3/memories` |
| `memory_history` | `id` (required) | `GET /v3/memories/{id}/history` |
| `forget_memory` | `id` (required) | `DELETE /v3/memories/{id}` |
| `restore_memory` | `id` (required) | `POST /v3/memories/{id}/restore` |
| `add_document` | `content` or `url`, `title`, `extract` (true), `wait` (false) | `POST /v3/documents` (sets `customId` to `title`) |
| `get_profile` | | `GET /v4/profile` |
| `list_containers` | | `GET /v1/containers` |

Tool results are plain text. `search_memories` lists hits as
`[n] fact|passage (from <title>) id=... score=...` (text cut at 700
characters). `add_document` without `wait` returns the job id immediately
(HTTP timeout 60 s); with `wait` it blocks up to an hour. Re-adding the same
`title` replaces the earlier document; with no title and no URL, each call adds
a new one. Failures come back as `isError` results (`smem API <code>: <message>`
or `cannot reach smem at <url>`); the HTTP timeout is 600 s. The bridge does not
expose `PATCH`, forget-by-query, the graph or the worker routes.

At `initialize` the bridge sends these instructions (the default container
name is filled in):

> Long-term memory, stored on a local server (default container "claude").
> At the start of a task, call get_profile once: it returns the stable facts
> and preferences for this space (and what changed recently) in one call.
> Before answering a question that may depend on something learned in an
> earlier session, call search_memories. When the user states a durable
> preference, decision or fact about their projects, call add_memory with ONE
> self-contained fact; a fact that contradicts an existing memory supersedes
> it (the old version is kept as history) and a restatement is dropped as a
> duplicate. search_memories is fast (~0.1 s); ask_memory writes a cited
> answer with a local model and takes 40-120 s, so prefer search_memories
> unless a synthesised answer is really needed.

(Abridged from the `INSTRUCTIONS` constant in the file.)

## CLI

```sh
python -m smem [-c container] [--db path] <command> [options]
```

The CLI opens the SQLite file directly and calls the model servers directly
(`SMEM_NODES`, ports `SMEM_PORT_EMB`/`_RRK`/`_LLM`); it does not use the HTTP
API and works without the server running. The global flags go **before** the
command.

| Flag | Default | Meaning |
|---|---|---|
| `--db` | `$SMEM_DB`, else `~/.local/share/smem/smem.db` | SQLite file |
| `-c`, `--container` | `default` | Container for the command (`stats -c '*'` = every container) |

| Command | Arguments and flags | Does |
|---|---|---|
| `health` | | Probes each node's embedder, reranker and LLM; exit 1 if any is down |
| `ingest` | `path` (file or directory), `--no-extract`, `--sequential` | Ingests `.md .txt .rst .py .sh .c .h .conf .json` files (directories recursively, skipping `.git`); each file's relative path is its title and `custom_id`. `--sequential` is the old one-document-at-a-time path, for comparison |
| `search` | `query`, `-k` (8), `--half-life DAYS` | Prints hits with vector, rerank and decay scores. **Always reranks** (no flag to turn it off), unlike the HTTP default |
| `ask` | `query`, `-k` (8), `--half-life DAYS` | Cited answer plus sources and timings |
| `remember` | `fact` | Stores one fact; reports a duplicate |
| `list` | `--history` | Live memories newest first; `--history` adds superseded (`OLD`) and forgotten (`GONE`) rows |
| `forget` | `query`, `--yes` | Dry run by default; `--yes` forgets the matches (threshold 0.60) |
| `stats` | | Counts for the container |
| `compress` | `query`, `-k` (8), `--half-life` | Corpus tokens vs retrieved-context tokens |
| `reembed` | | Re-embeds every chunk and memory after an embedder change, in one transaction. Stop the API first |

There is deliberately no `smem` console script: `smem` is an existing Linux
memory-reporting tool, and a script of that name would shadow it. The package
installs one script, `smem-server`, an alias for `python -m smem.server`
(`[project.scripts]` in `pyproject.toml`). Server flags: `--db`,
`--container` (default `default`), `--host` (`127.0.0.1`), `--port` (8900),
`--no-telemetry`, `--no-worker`.

## Latency and failure behaviour

| Call | Typical time | Notes |
|---|---|---|
| `POST /v4/search` | ~0.1 s | Embedding plus a numpy scan. `"rerank": true` adds a cross-encoder pass over 40 candidates, measured at 5-17 s on the reference CPUs (about 21 s end to end in the README). The parameter is `rerank`, default `false` |
| `POST /v1/ask` | tens of seconds (40-120 s quoted by the MCP tool) | Always reranks, then generates up to 400 tokens on a CPU LLM |
| `POST /v3/memories`, `PATCH` | seconds | Embedding plus a judge call when a close neighbour exists. These hold the server's single write lock while they wait |
| `POST /v3/documents` | returns immediately (202) | About a minute per 3,000 characters to finish; `extract: false` is much faster |

The server pairs one request thread per connection with one background worker,
and a llama-server serves one request at a time, so a search can queue behind
an extraction when both lanes share a host (see `smem/pool.py`).

**With the model servers down**, any route that needs a model (search, ask,
remember, PATCH, forget-by-query) does not fail at once. `Pool.post` makes up
to 8 attempts, moving to another node after each failure and sleeping only after
it has tried every node: `min(4 s * rounds, 30 s)`, where a round is one pass
over the nodes. The total back-off therefore depends on the node count in
`SMEM_NODES`:

| Nodes | Sleeps | Total wait before the error |
|---|---|---|
| 1 (the default, `127.0.0.1`) | 4, 8, 12, 16, 20, 24, 28 s | about 112 s, i.e. roughly two minutes |
| 2 | 4, 8, 12 s | about 24 s |
| 3 | 4, 8 s | about 12 s |
| 6 | 4 s | about 4 s |

(Connection refusals return instantly, so the sleeps dominate. A server that
accepts the connection but hangs is different: each attempt can wait up to the
600 s pool timeout.) The caller then gets
`500 {"error": "NodeError: all 8 attempts failed, last=<node>: <reason>"}`.
During that wait the request thread is blocked, and for `POST /v3/memories` and
`PATCH` the write lock is held, so other writes queue behind it. Reads that need
no model (lists, history, profile, stats, document fetch) are unaffected.
