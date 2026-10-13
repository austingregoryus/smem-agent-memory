<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Console

Open **`http://localhost:8900/`**. The API serves the console itself, as one
HTML file ([`smem/ui/index.html`](../smem/ui/index.html)) with no build step.
The only external script is d3, for the graph view, loaded from a pinned CDN
URL with subresource integrity. It is dark by default, and light when the OS
asks for it or the toggle says so.

The left rail frames everything:

- **Space switcher** (top). A space is a container tag. Type a new name to
  create one.
- **Views** (middle).
- **Substrate** (bottom). This shows what the background worker is doing.
  With node telemetry on (`SMEM_NODE_PROBE=ssh`), it also shows each node's
  temperature and memory. With telemetry off, it says so.

| View | What it does |
|---|---|
| **Home** | The space's **profile**, split into static (preferences and facts) and dynamic (recent episodes and updates). Also: counts, the type mix, the latest memories, memories per hour and facts per document. |
| **Memories** | Filter by text, status (live, superseded, forgotten), type and document. A detail panel shows relations (extends and extended-by) and the version timeline, with **Update** (stores a new version), **Forget** and **Restore**. |
| **Documents** | The processing queue with live status. Add documents as text, a public URL or a file; read a document and the facts extracted from it; delete it (a hard delete, with confirmation). |
| **Memory graph** | Documents appear as cards, memories as dots coloured by type, and older versions and forgotten memories as rings. Edges show source, updates (the version chain), extends (dashed) and similar documents (dotted). It has a legend with counts and a highlight search; click a node for its neighbours. |
| **Chat** | Ask the space a question. Answers cite their sources inline, and the sources expand under the answer. The thread is kept per space for the browser session. |
| **Activity** | Dreaming progress with pause and resume, and calibration (labels, fitted thresholds, refit). Also: requests per minute, per-endpoint p50 and p95, and recent requests. |
| **Connect** | MCP setup, HTTP examples, the endpoint list, and token entry when authentication is on. |

**Keyboard:** `g` then `h` `m` `d` `g` `c` `a` switches view, and `/`
focuses the page's search.

**Labelling.** Setting a memory's type, or pressing ✓ or ✗ on a suggested
extends link, saves a label. Labels re-fit the background judges' thresholds
(Activity → Calibration), and the new fit is re-applied to every past
decision.

**Responsiveness.** Reads run on their own read-only SQLite connection and
take no lock. The console stays responsive while an `ask` or an ingest is
running.

**Authentication.** When the server runs with `SMEM_TOKEN`, the console asks
for the token on its Connect page and keeps it in the browser's local storage.
