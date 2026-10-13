<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Results

Measurements behind the design decisions, in the order they were made. All
were taken on the reference deployment (Intel VCA 2 nodes); each file says
what transfers to other hardware.

| File | Date | Question |
|---|---|---|
| [RESULTS.md](RESULTS.md) | 2026-09-22 | Does retrieval over extracted facts beat raw chunks? Ingest cost, temporal truth, three silent failures, memory sizing. |
| [BAKEOFF.md](BAKEOFF.md) | 2026-09-22 | Which LLM should extract facts? Four models against gemma-4-E4B. |
| [DECIDE.md](DECIDE.md) | 2026-09-23 | Letter-logprob judging versus grammar-constrained answers, and smaller judge models. |
| [EMBED_BAKEOFF.md](EMBED_BAKEOFF.md) | 2026-10-07 | EmbeddingGemma 2 versus Qwen3-Embedding-0.6B, and the switch. |
