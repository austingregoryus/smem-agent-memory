#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Intel VCA 2 reference deployment: make smem survive a host reboot. Run on
# the VCA host, as root, with a copy of this repository's smem/ package in
# /root/supermem (smem-api.service's WorkingDirectory):
#
#   deploy/vca2/install_host.sh      install + enable (does not reboot)
#
# Installs only the smem side:
#   smem-api.service (this directory)  -> /etc/systemd/system, enabled
#   the model servers as real units on each node's disk (services.sh install)
#
# The card itself -- vca2-boot, NAT, clean shutdown and vca2-card.service,
# which bring the nodes up on every host boot -- comes from the VCA 2 repo,
# https://github.com/austingregoryus/vca2 . Install that first; smem-api is
# deliberately not ordered after it (see smem-api.service).
#
# NODE_PW (the nodes' root password) is read by services.sh from the
# environment, and by smem-api from /root/supermem/smem.env.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

install -m 0644 "$HERE/smem-api.service" /etc/systemd/system/smem-api.service

# A transient smem-api from `services.sh api` would shadow the unit file.
systemctl stop smem-api 2>/dev/null || true
systemctl reset-failed smem-api 2>/dev/null || true
systemctl daemon-reload
systemctl enable smem-api.service

# Model servers as installed, enabled units on each node's own disk image.
"$HERE/services.sh" install

systemctl start smem-api.service
systemctl --no-pager --lines=0 status smem-api.service | grep -E '●|Active'
