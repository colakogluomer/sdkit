#!/usr/bin/env bash
echo "required|python3|install Python 3 (see pyproject.toml for the version)"
echo "optional|ruff|pip install ruff (lint and post-edit formatting are skipped without it)"
echo "optional|pytest|pip install pytest (falls back to unittest discover)"
echo "optional|mypy|pip install mypy (only used when the project configures it)"
echo "optional|uv|brew install uv (only for projects with uv.lock)"
