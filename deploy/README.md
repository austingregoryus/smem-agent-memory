<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Deployment files

| Path | What |
|---|---|
| [`smem.env.example`](smem.env.example) | Every setting, commented out at its default. Copy to `/etc/smem/smem.env`. |
| [`systemd/`](systemd/) | Units for one machine: the three model servers (`smem-emb`, `smem-rrk`, `smem-llm`) and the API (`smem-api`) |
| [`vca2/`](vca2/) | The reference deployment on Intel VCA 2 cards, as it runs there |

Walk-through, multi-machine setups and security notes:
[`docs/DEPLOYMENT.md`](../docs/DEPLOYMENT.md).
