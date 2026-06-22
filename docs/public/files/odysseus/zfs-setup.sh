#!/usr/bin/env bash
# ZFS dataset for Odysseus model storage.
# Replace "yourpool" with the actual pool name.
# See: https://docs.45homelab.com/articles/odysseus/#step-4-zfs-dataset-for-model-files
set -euo pipefail

POOL="${POOL:-yourpool}"
DATASET="${POOL}/models"

zfs create "$DATASET"
zfs set recordsize=1M   "$DATASET"
zfs set atime=off       "$DATASET"
zfs set compression=lz4 "$DATASET"

echo "Created $DATASET with: recordsize=1M, atime=off, compression=lz4"
zpool get ashift "$POOL"
