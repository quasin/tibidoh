#!/usr/bin/env bash

dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/.."
cd "$dir"
if [ "$(date -u '+%H')" = "00" ] && [ "$(date -u '+%M')" = "00" ]; then
    git pull --rebase
    cp "$dir/data/sub.txt" "$dir/data/share/log/sub$(date -u '+%Y%m%d').txt"
    echo "" > "$dir/data/sub.txt"
    hash=$(ipfs add -r --nocopy -Q "$dir/data/share/log")
    ipfspub $hash
fi
if [ "$(date -u '+%M')" = "00" ] || [ "$(date -u '+%M')" = "30" ]; then
    for dir in apps/*/; do
      if [ -f "$dir/min30.sh" ]; then
        bash "$dir/min30.sh"
      fi
    done
    ipfspub 'Ok!'
fi
