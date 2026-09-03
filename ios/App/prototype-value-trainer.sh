#!/bin/bash
# PROTOTYPE — throwaway value-trainer UI. Serves the HTML and opens it.
set -euo pipefail
cd "$(dirname "$0")"
PORT="${PORT:-8765}"
URL="http://127.0.0.1:${PORT}/prototype-value-trainer.html?variant=A"
if command -v uv >/dev/null 2>&1; then
  PY=(uv run python)
else
  PY=(python3)
fi
echo "prototype → $URL"
open "$URL" 2>/dev/null || true
exec "${PY[@]}" -m http.server "$PORT" --bind 127.0.0.1
