# SPDX-License-Identifier: MIT
"""smem -- a local, self-hosted memory layer for agents.

A Supermemory-shaped API (container tags, extracted memories, temporal truth,
soft-delete forgetting, recency decay) backed by SQLite + numpy and three
local llama.cpp servers (embedder, reranker, LLM). No API keys, no egress.
It was first built to run on an Intel VCA 2 card; see deploy/vca2/.
"""

from .engine import Engine
from .models import Models
from .pool import Pool
from .store import Store

__all__ = ["Engine", "Models", "Pool", "Store"]
__version__ = "0.3.0"
