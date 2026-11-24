#!/bin/zsh
set -eu
cd -- "${0:A:h}"
if [[ -x /opt/homebrew/bin/python3.13 ]]; then
  exec /opt/homebrew/bin/python3.13 Scripts/build.py
elif [[ -x /opt/homebrew/bin/python3.14 ]]; then
  exec /opt/homebrew/bin/python3.14 Scripts/build.py
else
  print '請先安裝 Homebrew Python 3.13 或 3.14。'
  exit 1
fi
