#!/bin/sh

# Compile only the aMACI AddNewKey circuit.
# Usage:
# - ./start_new_circuit_addnewkey_only.sh
# - ./start_new_circuit_addnewkey_only.sh all
# - ./start_new_circuit_addnewkey_only.sh 2-1-1-5
# - ./start_new_circuit_addnewkey_only.sh 2-1-1-5 4-2-2-25
#
# With no args or "all", it compiles these POWER sizes:
# - 2-1-1-5
# - 4-2-2-25
# - 6-3-3-125
# - 9-4-3-125
#
# Only stateTreeDepth is used from POWER.
# Outputs per POWER:
# - R1CS / WASM under build/amaci_new/$POWER/<circuit_id>/
# - BIN at build/amaci_new/$POWER/bin/addKey.bin
# - ZKEY at build/amaci_new/$POWER/zkey/addKey.zkey
# - Verification key at build/amaci_new/$POWER/verification_key/addKey/verification_key.json

set -e

DEFAULT_POWERS="2-1-1-5 4-2-2-25 6-3-3-125 9-4-3-125"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
NEW_CIRCUITS_DIR="$ROOT_DIR/new_circuits"
PTAU="$ROOT_DIR/ptau/powersOfTau28_hez_final_22.ptau"
NODE_MEMORY_MB=98304

BUILD_CIRCUIT="/Users/bun/DoraFactory/circom-witnesscalc/target/release/build-circuit"
CONFIG_FILE="$NEW_CIRCUITS_DIR/circomkit.json"
CONFIG_BACKUP="$NEW_CIRCUITS_DIR/circomkit.json.bak"

if [ "$#" -eq 0 ] || [ "$1" = "all" ]; then
  POWERS="$DEFAULT_POWERS"
else
  POWERS="$*"
fi

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

if [ ! -f "$PTAU" ]; then
  echo "Error: PTAU file not found: $PTAU"
  exit 1
fi

if ! command -v pnpm >/dev/null 2>&1; then
  echo "Error: pnpm not found in PATH"
  exit 1
fi

if ! command -v snarkjs >/dev/null 2>&1; then
  echo "Error: snarkjs not found in PATH"
  exit 1
fi

is_uint() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

restore_config() {
  if [ -f "$CONFIG_BACKUP" ]; then
    mv "$CONFIG_BACKUP" "$CONFIG_FILE"
  fi
}

trap restore_config EXIT

cp "$CONFIG_FILE" "$CONFIG_BACKUP"

export NODE_OPTIONS="--max-old-space-size=$NODE_MEMORY_MB"

for POWER in $POWERS; do
  IFS='-' read -r STATE_TREE_DEPTH INT_STATE_TREE_DEPTH VOTE_OPTION_TREE_DEPTH MESSAGE_BATCH_SIZE <<EOF
$POWER
EOF

  if [ -z "$STATE_TREE_DEPTH" ] || [ -z "$INT_STATE_TREE_DEPTH" ] || [ -z "$VOTE_OPTION_TREE_DEPTH" ] || [ -z "$MESSAGE_BATCH_SIZE" ]; then
    echo "Error: invalid POWER format: $POWER"
    echo "Expected format: stateTreeDepth-intStateTreeDepth-voteOptionTreeDepth-messageBatchSize (e.g. 9-4-3-125)"
    exit 1
  fi

  if ! is_uint "$STATE_TREE_DEPTH" || ! is_uint "$INT_STATE_TREE_DEPTH" || ! is_uint "$VOTE_OPTION_TREE_DEPTH" || ! is_uint "$MESSAGE_BATCH_SIZE"; then
    echo "Error: POWER must contain positive integers only: $POWER"
    exit 1
  fi

  ADDKEY_CIRCUIT="AddNewKey_amaci_${STATE_TREE_DEPTH}"
  OUTPUT_DIR="$ROOT_DIR/build/amaci_new/$POWER"

  if ! grep -q "\"$ADDKEY_CIRCUIT\"[[:space:]]*:" "$NEW_CIRCUITS_DIR/circom/circuits.json"; then
    echo "Error: circuit \"$ADDKEY_CIRCUIT\" is not defined in $NEW_CIRCUITS_DIR/circom/circuits.json"
    exit 1
  fi

  mkdir -p "$OUTPUT_DIR/bin"
  mkdir -p "$OUTPUT_DIR/zkey"
  mkdir -p "$OUTPUT_DIR/verification_key/addKey"

  node -e "
const fs = require('fs');
const configPath = process.argv[1];
const outDir = process.argv[2];
const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
cfg.dirBuild = outDir;
fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2));
" "$CONFIG_FILE" "$OUTPUT_DIR"

  echo "========================================"
  echo "Compiling $ADDKEY_CIRCUIT for POWER $POWER"
  echo "========================================"

  (cd "$NEW_CIRCUITS_DIR" && pnpm exec circomkit compile "$ADDKEY_CIRCUIT")

  ADDKEY_R1CS="$OUTPUT_DIR/$ADDKEY_CIRCUIT/$ADDKEY_CIRCUIT.r1cs"
  ADDKEY_WASM="$OUTPUT_DIR/$ADDKEY_CIRCUIT/${ADDKEY_CIRCUIT}_js/${ADDKEY_CIRCUIT}.wasm"
  SRC_CIRCOM="$NEW_CIRCUITS_DIR/circom/main/${ADDKEY_CIRCUIT}.circom"
  OUT_BIN="$OUTPUT_DIR/bin/addKey.bin"

  if [ ! -f "$ADDKEY_R1CS" ]; then
    echo "Error: R1CS not found: $ADDKEY_R1CS"
    exit 1
  fi

  if [ ! -f "$ADDKEY_WASM" ]; then
    echo "Error: WASM not found: $ADDKEY_WASM"
    exit 1
  fi

  if [ ! -f "$SRC_CIRCOM" ]; then
    echo "Error: instantiated circuit not found: $SRC_CIRCOM"
    exit 1
  fi

  echo "Building addKey.bin..."
  "$BUILD_CIRCUIT" "$SRC_CIRCOM" "$OUT_BIN"

  echo "Generating zkeys..."
  snarkjs g16s "$ADDKEY_R1CS" "$PTAU" "$OUTPUT_DIR/zkey/addKey_0.zkey"

  echo "Contributing to ceremony and exporting verification key..."
  echo "entropy_$(date +%s)" | snarkjs zkc "$OUTPUT_DIR/zkey/addKey_0.zkey" "$OUTPUT_DIR/zkey/addKey.zkey" --name="DoraHacks" -v
  snarkjs zkev "$OUTPUT_DIR/zkey/addKey.zkey" "$OUTPUT_DIR/verification_key/addKey/verification_key.json"

  echo ""
  echo "Done. AddNewKey artifacts are in: $OUTPUT_DIR"
  echo "  Circuit ID: $ADDKEY_CIRCUIT"
  echo "  WASM: $ADDKEY_WASM"
  echo "  BIN:  $OUT_BIN"
  echo "  ZKEY: $OUTPUT_DIR/zkey/addKey.zkey"
  echo "  VKEY: $OUTPUT_DIR/verification_key/addKey/verification_key.json"
  echo ""
done

echo "All requested AddNewKey builds completed."
