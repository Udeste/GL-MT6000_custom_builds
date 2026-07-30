#!/bin/sh
set -e

CURRENT_BRANCH=$(git branch --show-current)

echo ">>> Removing old bins"
rm -fr bin/*

echo ">>> Updating feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

make defconfig

echo ">>> Downloading package sources..."
make download -j12

echo ">>> Building (this will take a while)..."
make -j12 || {
    echo ">>> Parallel build failed, retrying single-threaded for better error output..."
    make -j1 V=s
}

echo ">>> Done! Firmware is in: bin/targets/"
