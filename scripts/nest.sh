#!/bin/bash
set -euo pipefail

SRCROOT=$(git rev-parse --show-toplevel)

if [ ! -d "$HOME/.nest/bin" ] || [ ! -f "$HOME/.nest/bin/nest" ]; then
    echo "nest command not found globally or locally. Installing..."
    curl -s https://raw.githubusercontent.com/mtj0928/nest/main/Scripts/install.sh | bash

    if [ ! -d "$HOME/.nest/bin" ] || [ ! -f "$HOME/.nest/bin/nest" ]; then
        echo "Failed to install nest command. Please install it manually."
        exit 1
    fi
    echo "nest installed successfully!"

    "$HOME/.nest/bin/nest" bootstrap "$SRCROOT/nestfile.yaml"
fi

"$HOME/.nest/bin/nest" "$@"
