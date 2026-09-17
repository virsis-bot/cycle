#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
exec python3 -I "$D/fingerprint.py" "${CLAUDE_PROJECT_DIR:-$(pwd)}"
