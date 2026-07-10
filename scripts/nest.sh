#!/bin/bash
set -euo pipefail

SRCROOT=$(git rev-parse --show-toplevel)

# Pin the third-party installer to an immutable commit SHA (tag 0.7.1), not a
# tag or branch — tags are mutable, so a compromised upstream repo could move
# one and this supply-chain fetch would run attacker code, including in CI
# jobs that hold write tokens. Bump deliberately when adopting a new nest
# release, resolving the new tag to its commit SHA.
NEST_VERSION="0.7.1"
NEST_REVISION="d31cf735eece736c5e75f479db82c6e60cf34e23" # tag 0.7.1

if [ ! -d "$HOME/.nest/bin" ] || [ ! -f "$HOME/.nest/bin/nest" ]; then
    echo "nest command not found globally or locally. Installing nest ${NEST_VERSION}..."
    curl -sSf "https://raw.githubusercontent.com/mtj0928/nest/${NEST_REVISION}/Scripts/install.sh" | bash

    if [ ! -d "$HOME/.nest/bin" ] || [ ! -f "$HOME/.nest/bin/nest" ]; then
        echo "Failed to install nest command. Please install it manually."
        exit 1
    fi
    echo "nest installed successfully!"

    "$HOME/.nest/bin/nest" bootstrap "$SRCROOT/nestfile.yaml"
fi

"$HOME/.nest/bin/nest" "$@"
