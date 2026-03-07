#!/bin/sh

# Compile only the aMACI ProcessMessages circuit for a given POWER tuple.
# Outputs:
# - R1CS / WASM under build/amaci_new/$POWER/<circuit_id>/
# - BIN at build/amaci_new/$POWER/bin/msg.bin
# - ZKEY at build/amaci_new/$POWER/zkey/msg.zkey
# - Verification key at build/amaci_new/$POWER/verification_key/msg/verification_key.json

set -e

POWER="${1:-2-1-1-5}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
NEW_CIRCUITS_DIR="$ROOT_DIR/new_circuits"
OUTPUT_DIR="$ROOT_DIR/build/amaci_new/$POWER"
PTAU="$ROOT_DIR/ptau/powersOfTau28_hez_final_22.ptau"
NODE_MEMORY_MB=98304

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

MSG_CIRCUIT="ProcessMessages_amaci_${STATE_TREE_DEPTH}-${VOTE_OPTION_TREE_DEPTH}-${MESSAGE_BATCH_SIZE}"

CONFIG_FILE="$NEW_CIRCUITS_DIR/circomkit.json"
CONFIG_BACKUP="$NEW_CIRCUITS_DIR/circomkit.json.bak"

restore_config() {
  if [ -f "$CONFIG_BACKUP" ]; then
    mv "$CONFIG_BACKUP" "$CONFIG_FILE"
  fi
}

trap restore_config EXIT

if ! grep -q "\"$MSG_CIRCUIT\"[[:space:]]*:" "$NEW_CIRCUITS_DIR/circom/circuits.json"; then
  echo "Error: circuit \"$MSG_CIRCUIT\" is not defined in $NEW_CIRCUITS_DIR/circom/circuits.json"
  exit 1
fi

mkdir -p "$OUTPUT_DIR/bin"
mkdir -p "$OUTPUT_DIR/zkey"
mkdir -p "$OUTPUT_DIR/verification_key/msg"

cp "$CONFIG_FILE" "$CONFIG_BACKUP"
node -e "
const fs = require('fs');
const configPath = process.argv[1];
const outDir = process.argv[2];
const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
cfg.dirBuild = outDir;
fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2));
" "$CONFIG_FILE" "$OUTPUT_DIR"

export NODE_OPTIONS="--max-old-space-size=$NODE_MEMORY_MB"

echo "Compiling $MSG_CIRCUIT with circomkit..."
(cd "$NEW_CIRCUITS_DIR" && pnpm exec circomkit compile "$MSG_CIRCUIT")

MSG_R1CS="$OUTPUT_DIR/$MSG_CIRCUIT/$MSG_CIRCUIT.r1cs"
MSG_WASM="$OUTPUT_DIR/$MSG_CIRCUIT/${MSG_CIRCUIT}_js/${MSG_CIRCUIT}.wasm"
SRC_CIRCOM="$NEW_CIRCUITS_DIR/circom/main/${MSG_CIRCUIT}.circom"
OUT_BIN="$OUTPUT_DIR/bin/msg.bin"

if [ ! -f "$MSG_R1CS" ]; then
  echo "Error: R1CS not found: $MSG_R1CS"
  exit 1
fi

if [ ! -f "$MSG_WASM" ]; then
  echo "Error: WASM not found: $MSG_WASM"
  exit 1
fi

if [ ! -f "$SRC_CIRCOM" ]; then
  echo "Error: instantiated circuit not found: $SRC_CIRCOM"
  exit 1
fi

echo "Building msg.bin..."
"$BUILD_CIRCUIT" "$SRC_CIRCOM" "$OUT_BIN"

echo "Generating zkeys..."
snarkjs g16s "$MSG_R1CS" "$PTAU" "$OUTPUT_DIR/zkey/msg_0.zkey"

echo "Contributing to ceremony and exporting verification key..."
echo "entropy_$(date +%s)" | snarkjs zkc "$OUTPUT_DIR/zkey/msg_0.zkey" "$OUTPUT_DIR/zkey/msg.zkey" --name="DoraHacks" -v
snarkjs zkev "$OUTPUT_DIR/zkey/msg.zkey" "$OUTPUT_DIR/verification_key/msg/verification_key.json"

echo ""
echo "Done. ProcessMessages artifacts are in: $OUTPUT_DIR"
echo "  Circuit ID: $MSG_CIRCUIT"
echo "  WASM: $MSG_WASM"
echo "  BIN:  $OUT_BIN"
echo "  ZKEY: $OUTPUT_DIR/zkey/msg.zkey"
echo "  VKEY: $OUTPUT_DIR/verification_key/msg/verification_key.json"
