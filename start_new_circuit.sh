#!/bin/sh

# Compile new aMACI 2-1-1-5 circuits into .bin using circom-witnesscalc.
# Flow:
# 1) Use circomkit to compile parameterized circuits (creates R1CS + circom/main/*.circom)
# 2) Use build-circuit to compile those instantiated circuits into .bin

set -e

POWER="${1:-2-1-1-5}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
NEW_CIRCUITS_DIR="$ROOT_DIR/new_circuits"
OUTPUT_DIR="$ROOT_DIR/build/amaci_new/$POWER"

# circom-witnesscalc path
BUILD_CIRCUIT="/Users/bun/DoraFactory/circom-witnesscalc/target/release/build-circuit"

if [ ! -f "$BUILD_CIRCUIT" ]; then
  echo "Error: build-circuit not found at $BUILD_CIRCUIT"
  echo "Please compile circom-witnesscalc first:"
  echo "  cd /Users/bun/DoraFactory/circom-witnesscalc"
  echo "  cargo build --release"
  exit 1
fi

if [ ! -d "$NEW_CIRCUITS_DIR" ]; then
  echo "Error: new_circuits directory not found at $NEW_CIRCUITS_DIR"
  exit 1
fi

if ! command -v pnpm >/dev/null 2>&1; then
  echo "Error: pnpm not found in PATH"
  exit 1
fi

mkdir -p "$OUTPUT_DIR/bin"

CONFIG_FILE="$NEW_CIRCUITS_DIR/circomkit.json"
CONFIG_BACKUP="$NEW_CIRCUITS_DIR/circomkit.json.bak"

restore_config() {
  if [ -f "$CONFIG_BACKUP" ]; then
    mv "$CONFIG_BACKUP" "$CONFIG_FILE"
  fi
}

trap restore_config EXIT

cp "$CONFIG_FILE" "$CONFIG_BACKUP"
node -e "
const fs = require('fs');
const configPath = process.argv[1];
const outDir = process.argv[2];
const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
cfg.dirBuild = outDir;
fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2));
" "$CONFIG_FILE" "$OUTPUT_DIR"

# circuit name -> output bin filename
CIRCUIT_MAP="
AddNewKey_amaci_2 addKey
ProcessDeactivateMessages_amaci_2-5 deactivate
ProcessMessages_amaci_2-1-5 msg
TallyVotes_amaci_2-1-1 tally
"

echo "Compiling circuits with circomkit (R1CS generation)..."
echo "$CIRCUIT_MAP" | while read -r circuit_name bin_name; do
  [ -z "$circuit_name" ] && continue
  (cd "$NEW_CIRCUITS_DIR" && pnpm exec circomkit compile "$circuit_name")
done

echo ""
echo "Building .bin files with circom-witnesscalc..."
echo "$CIRCUIT_MAP" | while read -r circuit_name bin_name; do
  [ -z "$circuit_name" ] && continue
  src_circom="$NEW_CIRCUITS_DIR/circom/main/${circuit_name}.circom"
  out_bin="$OUTPUT_DIR/bin/${bin_name}.bin"

  if [ ! -f "$src_circom" ]; then
    echo "Error: instantiated circuit not found: $src_circom"
    exit 1
  fi

  echo "  Building ${bin_name}.bin from ${circuit_name}..."
  "$BUILD_CIRCUIT" "$src_circom" "$out_bin"
done

echo ""
echo "Done. Binaries are in: $OUTPUT_DIR/bin"
