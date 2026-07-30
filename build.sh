#!/bin/sh
# Self-contained local build: checks out the upstream OpenWrt tree, overlays this
# repo's files/ + mt6000.config, and builds — mirroring the GitHub Actions CI.
#
# Meant to run inside the Debian container from shell.nix (OpenWrt won't build on
# NixOS natively, nor as root). shell.nix sets BUILDER_DIR and OPENWRT_DIR for you.
#
# Overridable via env:
#   BUILDER_DIR         this repo (default: the script's own directory)
#   OPENWRT_DIR         where the OpenWrt tree lives (default: ../openwrt)
#   REMOTE_REPOSITORY   upstream git URL (default: pesa1234/openwrt)
#   OPENWRT_BRANCH      pin a branch (default: newest non-test/beta next-* branch)
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BUILDER_DIR=${BUILDER_DIR:-$SCRIPT_DIR}
OPENWRT_DIR=${OPENWRT_DIR:-$BUILDER_DIR/../openwrt}
REMOTE_REPOSITORY=${REMOTE_REPOSITORY:-https://github.com/pesa1234/openwrt.git}
JOBS=$(nproc)

# 1. Determine the branch (same logic as the CI's check_commits job)
if [ -n "$OPENWRT_BRANCH" ]; then
    BRANCH=$OPENWRT_BRANCH
else
    echo ">>> Detecting newest upstream next-* branch..."
    BRANCH=$(git ls-remote "$REMOTE_REPOSITORY" 'refs/heads/next-*' \
        | sed -e 's|.*refs/heads/||' | grep -viE 'test|beta' | sort -V | tail -n1)
fi
[ -n "$BRANCH" ] || { echo "!!! Could not determine upstream branch" >&2; exit 1; }
echo ">>> Using branch: $BRANCH"

# 2. Clone or update the OpenWrt tree at that branch
if [ ! -d "$OPENWRT_DIR/.git" ]; then
    echo ">>> Cloning $REMOTE_REPOSITORY into $OPENWRT_DIR ..."
    git clone --branch "$BRANCH" --single-branch "$REMOTE_REPOSITORY" "$OPENWRT_DIR"
else
    echo ">>> Updating existing tree in $OPENWRT_DIR ..."
    git -C "$OPENWRT_DIR" fetch origin "$BRANCH"
    git -C "$OPENWRT_DIR" checkout -B "$BRANCH" FETCH_HEAD
fi

# 3. Overlay this repo's customizations (like the CI's "Setup custom files" step)
echo ">>> Overlaying files/ and mt6000.config ..."
mkdir -p "$OPENWRT_DIR/files"
cp -a "$BUILDER_DIR/files/." "$OPENWRT_DIR/files/"
cp "$BUILDER_DIR/mt6000.config" "$OPENWRT_DIR/.config"

cd "$OPENWRT_DIR"

echo ">>> Removing old bins"
rm -fr bin/*

echo ">>> Updating feeds..."
./scripts/feeds update -a
./scripts/feeds install -a
# run again because sometimes it misses some dependencies
./scripts/feeds install -a

make defconfig

echo ">>> Downloading package sources..."
make download -j"$JOBS"

echo ">>> Building (this will take a while)..."
make -j"$JOBS" || {
    echo ">>> Parallel build failed, retrying single-threaded for better error output..."
    make -j1 V=s
}

echo ">>> Done! Firmware is in: $OPENWRT_DIR/bin/targets/"
