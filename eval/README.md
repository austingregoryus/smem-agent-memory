<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Evaluation harnesses

These scripts produced the numbers in [`docs/results/`](../docs/results/).
They are **measurements, not tests**: each reports a score, not pass or fail.
The offline tests are in [`tests/`](../tests/).

All of them need the model servers running, except `bench_decide_score.py`.
Run them from the repository root.

## Portable: run against your own setup

| Script | Measures | Notes |
|---|---|---|
| `eval.py` | Retrieval recall@k, context size, answer quality, latency | The 15 questions are about the original test corpus (the VCA2 repository's `docs/`). Edit `QUESTIONS` for your own. |
| `demo.py` | Every behaviour end to end: ingest, update with history, duplicate drop, forget and restore, decay, profile | Uses a throwaway container and its own small corpus. Takes a few minutes. |
| `recon_eval.py` | Temporal-truth judge (DUPLICATE / UPDATE / DISTINCT) on 22 labelled pairs | 12 synthetic, 10 taken from real decisions. Written up in [RESULTS.md](../docs/results/RESULTS.md#4-temporal-truth). |
| `reconcile_repair.py` | Re-judges past supersede decisions with the current judge | A dry run unless `--apply`. A repair tool, kept with its measurement. |
| `bench_decide.py`, `bench_decide_score.py` | Typing and extends judges: letter logprobs versus grammar, with accuracy and calibration error | [DECIDE.md](../docs/results/DECIDE.md). `--node` defaults to `127.0.0.1`. |
| `bench_decide_data.py` | Dumps unlabelled samples from a database for hand labelling | |
| `import_labels.py` | Seeds calibration with hand labels | |

## Reference deployment only

These ran on the Intel VCA 2 nodes and assume their addresses, paths or
journals. They are kept because they are how the published numbers were
made; each says so in its header.

| Script | Measures |
|---|---|
| `bakeoff.py`, `nudge.py` | Extraction models compared on the real workload ([BAKEOFF.md](../docs/results/BAKEOFF.md)). Swaps the LLM on every node via `deploy/vca2/swap_llm.sh`. |
| `embed_bakeoff.py` | EmbeddingGemma 2 versus Qwen3-Embedding-0.6B ([EMBED_BAKEOFF.md](../docs/results/EMBED_BAKEOFF.md)) |
| `timeline.py` | Rebuilds per-node busy time during a past run from the nodes' journals |
| `bench_decide_small.sh` | `bench_decide.py` against small models on a spare port |

## Data (`data/`)

Recorded inputs and outputs, licensed CC BY 4.0:

| File | What |
|---|---|
| `decide_labels.json` | Hand labels for the decision bake-off: memory types and extends pairs. Four items drawn from the author's personal memory space are replaced with `[redacted: …]`. |
| `decide/*.json`, `decide/SCORES.txt` | Raw results per model and the score table |
| `bakeoff-results.json`, `.log` | Extraction bake-off output and transcript |
| `nudge-results.json` | The prompt-nudge follow-up |
| `queue-ingest.log`, `queue-eval.log` | Ingest and evaluation runs after least-loaded dispatch was introduced |
