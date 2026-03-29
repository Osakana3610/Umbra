#!/bin/sh

set -eu

ROOT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
BUNDLE_DIR="${2:-}"
SOURCE_DIR="$ROOT_DIR/MasterDataSource"
GENERATOR_DIR="$ROOT_DIR/Generator"
OUTPUT_DIR="$GENERATOR_DIR/Output"
OUTPUT_FILE="$OUTPUT_DIR/masterdata.json"
STATE_FILE="$OUTPUT_DIR/masterdata.inputs.sha256"

mkdir -p "$OUTPUT_DIR"

INPUT_HASH="$(python3 - "$ROOT_DIR" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys

root = Path(sys.argv[1])
targets = []

for relative_root in ("MasterDataSource", "Generator"):
    base = root / relative_root
    for path in base.rglob("*"):
        if not path.is_file():
            continue
        if relative_root == "Generator" and "Output" in path.relative_to(base).parts:
            continue
        targets.append(path)

targets.sort()
digest = sha256()
for path in targets:
    rel = path.relative_to(root).as_posix().encode("utf-8")
    digest.update(rel)
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")

print(digest.hexdigest())
PY
)"

NEEDS_REBUILD=1
if [ -f "$OUTPUT_FILE" ] && [ -f "$STATE_FILE" ]; then
    EXISTING_HASH="$(cat "$STATE_FILE")"
    if [ "$EXISTING_HASH" = "$INPUT_HASH" ]; then
        NEEDS_REBUILD=0
    fi
fi

if [ "$NEEDS_REBUILD" -eq 1 ]; then
    echo "[master-generator] rebuilding bundled master data"
    python3 "$GENERATOR_DIR/generate_master_db.py" \
        --source-dir "$SOURCE_DIR" \
        --output-file "$OUTPUT_FILE"
    printf '%s' "$INPUT_HASH" > "$STATE_FILE"
else
    echo "[master-generator] bundled master data is up to date"
fi

if [ ! -f "$OUTPUT_FILE" ]; then
    echo "[master-generator] missing generated file: $OUTPUT_FILE" >&2
    exit 1
fi

python3 - "$OUTPUT_FILE" <<'PY'
import json
import sys
from pathlib import Path

output_path = Path(sys.argv[1])
payload = json.loads(output_path.read_text(encoding="utf-8"))

required_top_level_keys = (
    "metadata",
    "races",
    "jobs",
    "aptitudes",
    "items",
    "titles",
    "superRares",
    "skills",
    "spells",
    "recruitNames",
    "enemies",
    "labyrinths",
)

missing = [key for key in required_top_level_keys if key not in payload]
if missing:
    raise SystemExit(f"[master-generator] invalid generated master data: missing {', '.join(missing)}")

recruit_names = payload["recruitNames"]
for key in ("male", "female", "unisex"):
    names = recruit_names.get(key)
    if not isinstance(names, list) or not names:
        raise SystemExit(f"[master-generator] invalid recruitNames.{key}")
PY

if [ -n "$BUNDLE_DIR" ]; then
    mkdir -p "$BUNDLE_DIR"
    cp "$OUTPUT_FILE" "$BUNDLE_DIR/masterdata.json"
    python3 - "$BUNDLE_DIR/masterdata.json" <<'PY'
import json
import sys
from pathlib import Path

bundle_file = Path(sys.argv[1])
json.loads(bundle_file.read_text(encoding="utf-8"))
PY
    echo "[master-generator] copied masterdata.json into app bundle"
fi
