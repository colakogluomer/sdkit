#!/usr/bin/env bash
# exit 0 when $1 contains a Python project (pyproject.toml, setup.py, setup.cfg or requirements.txt)
[ -n "$(find "${1:-.}" -maxdepth 3 \( -name node_modules -o -name .venv -o -name venv -o -name .git \) -prune -o \
  \( -name pyproject.toml -o -name setup.py -o -name setup.cfg -o -name requirements.txt \) -type f -print 2>/dev/null | head -1)" ]
