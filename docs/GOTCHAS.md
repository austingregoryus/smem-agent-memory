<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Gotchas

Every problem on this page failed **silently**. The API returned 200, the
run reported success, and the data was wrong or missing. They are written down
because each one is easy to reintroduce when swapping a model or changing a
server flag.

## The models

smem is hardware-agnostic but **not model-agnostic**. The prompts, grammars
and output parsing in `smem/models.py` and `smem/engine.py` were written and
measured against exactly these three models:

| Stage | Model | Port | Why this one |
|---|---|---|---|
| Embedder | EmbeddingGemma 2, Q8_0 GGUF ([`ggml-org/embeddinggemma-2-GGUF`](https://huggingface.co/ggml-org/embeddinggemma-2-GGUF)) | 8080 | Ties Qwen3-Embedding-0.6B on recall, 2.6× the bulk throughput, 768 dimensions ([bake-off](results/EMBED_BAKEOFF.md)). Needs llama.cpp **b11476** or newer. |
| Reranker | Qwen3-Reranker-0.6B, Q8_0 GGUF | 8081 | Cross-encoder for the second retrieval stage |
| LLM | gemma-4-E4B-it, Q4_K_M GGUF | 8082 | Fact extraction, reconciliation, typing, answers. It caught 44% of the source's numbers in extraction, against 10% for a 3.2× faster model ([bake-off](results/BAKEOFF.md)). |

Swapping one is possible, but check what breaks:

- **A different embedder** needs its own query and document prompts
  (`QUERY_INSTRUCT` and `doc_text()` in `models.py`) and possibly a new `DIM`.
  It also invalidates every stored vector: stop the server, then run
  `python -m smem reembed`. A server that returns the wrong vector size is
  refused loudly, so this one at least is not silent.
- **A different reranker** must accept llama-server's `--reranking`
  endpoint. Its scores are only meaningful relative to each other.
- **A different LLM** is the risky one. Read the next two sections.

## A reasoning model returns an empty string

gemma-4-E4B is a reasoning model. Left to itself, it writes its chain of
thought into `reasoning_content` and only then begins `content`. Every
prompt here is long enough that it spent the whole token budget thinking,
returned `finish_reason: length`, and handed back `content: ""`. A full
22-file ingest completed "successfully" with **0 facts extracted**.

What works is `chat_template_kwargs: {"enable_thinking": false}` on every
request. `reasoning_budget` and `thinking_budget` were ignored by the
llama.cpp build in use. `reasoning_format: "none"` only stops llama-server
from *splitting* the channels: the model still thinks, and raw
`<|channel>thought` markers leak into the content.

If you swap the LLM, check that `content` is non-empty on a long extraction
prompt before trusting any ingest.

## A one-word classifier needs a grammar

Asked in free text to answer `DUPLICATE`, `UPDATE` or `DISTINCT`, the model
returned an empty string for *precisely the DUPLICATE cases*. Those fell
through to `DISTINCT`, and the duplicate was stored. Constraining the output
with GBNF (`root ::= "DUPLICATE" | "UPDATE" | "DISTINCT"`) makes a wrong
answer unrepresentable. On a 12-pair labelled set, accuracy went from
unusable to 12/12.

The background judges (typing and extends) went one step further. They
read each option's probability from the logprobs instead of generating an
answer at all ([DECIDE.md](results/DECIDE.md)).

## Heading paths read as filenames

Chunks are embedded with their heading path prepended, which helps retrieval
a lot. But handing the extractor a chunk that starts `THERMAL.md > ...` made
the model reply *"Please provide the content of THERMAL.md so I can extract
the durable facts."* Wrapping the body in `<document source="...">` tags
fixed it.

## Temporal truth was mostly wrong at first

The first reconciliation prompt scored 12/12 on synthetic pairs while the
real corpus was quietly losing facts. It treated "the same measurement under
different conditions" as an update: *MTU 1500 gives 2810 Mbit/s* was marked
superseded by *MTU 65521 gives 15934 Mbit/s*. Of 73 supersede decisions on a
real ingest, **50 were wrong**, and on ten pairs taken from real decisions it
got 1 right.

The fix is one rule applied before anything else: **if A and B can both be
true at the same time, it is never an UPDATE**. That rule plus worked examples
drawn from the failures brought real pairs to 8/10, and the full labelled set
to 19/22. A repair script re-judged the 73 links and restored 48 in about 70
short LLM calls, instead of a full re-ingest ([RESULTS.md](results/RESULTS.md)).
A test set that contains only the cases you already thought of will tell you
everything is fine.

## Memory sizing: RSS follows the micro-batch, not the model

The three GGUF files total about 6.3 GB, which looks small. llama-server's
resident set is dominated by its compute buffer, though, and that scales with
the **micro-batch** (`-ub`), not the model. With `-ub 2048`, each 0.6 GB
embedding or reranking model grew to about 5 GB. Together with the LLM, that
was 17.5 GB on a 15.4 GB machine, and the kernel killed the LLM mid-run.
Lowering `-ub` to 768 brought the total to about 8.8 GB.

The micro-batch cannot go arbitrarily low. Embedding models are
**non-causal**, so a single sequence must fit in one micro-batch, or
`llama_decode` returns -2. Size `-ub` to your longest chunk. smem caps chunks
at about 1400 characters (~350 tokens) and rerank pairs at about 1000.

## The reranker leaks; so, slowly, does the embedder

Under sustained reranking, llama-server's `--reranking` mode grows from
0.64 GB past 7 GB. Cap that process's memory so the service manager restarts
*it* (about 10 s), rather than letting the kernel's OOM killer pick the
largest process, which is the LLM. smem's dispatcher retries with backoff, so
a restart costs a few seconds, not a failed ingest.

The embedder leaks slowly: 0.3 GB to 3.0 GB over about 1.8 days. At its
memory cap it is not killed. It sits there reclaiming, and a five-token query
embed went from 0.03 s to 1.5 s. Restarting it daily (`RuntimeMaxSec=` in
systemd) avoids that.

## `MemoryMax=` is accepted and ignored on cgroup v1

On a cgroup v1 host (older kernels), the systemd property is `MemoryLimit=`.
systemd 249 **accepts** `MemoryMax=` there and reports it back when asked,
but writes `unlimited` into the cgroup. The cap looks applied and does
nothing. Check `memory.limit_in_bytes`, not `systemctl show`.

## `nohup … &` over SSH does not start a server

Backgrounding a model server over SSH with `nohup ... &` does not survive the
session closing. The server never starts, and every later request gets
`ECONNREFUSED`. Run the servers as service units.
