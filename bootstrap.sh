#!/usr/bin/env bash
# Generate the Xcode project and open it — one command from a fresh clone.
#
#   ./bootstrap.sh
#
# Optional: use your own bundle-id prefix (needed if the default is rejected by
# free Apple ID provisioning):
#
#   BUNDLE_PREFIX=com.yourname.watchvoicellm ./bootstrap.sh
#
# Signing itself is done in Xcode: pick your Team under each target's
# "Signing & Capabilities" (automatic signing is already configured).

set -euo pipefail
cd "$(dirname "$0")"

echo "▸ WatchVoiceLLM bootstrap"

# 1) XcodeGen ---------------------------------------------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "  · xcodegen not found — installing via Homebrew…"
  if ! command -v brew >/dev/null 2>&1; then
    echo "  ✗ Homebrew is required. Install it from https://brew.sh then re-run." >&2
    exit 1
  fi
  brew install xcodegen
fi
echo "  · xcodegen $(xcodegen --version 2>/dev/null | head -1)"

# 2) Optional bundle-id prefix rewrite -------------------------------------
if [[ -n "${BUNDLE_PREFIX:-}" ]]; then
  echo "  · rewriting bundle id prefix → ${BUNDLE_PREFIX}"
  # macOS/BSD sed in-place
  sed -i '' "s/com\.example\.watchvoicellm/${BUNDLE_PREFIX}/g" project.yml
fi

# 3) Generate ---------------------------------------------------------------
echo "  · generating WatchVoiceLLM.xcodeproj…"
xcodegen generate

# 4) Open -------------------------------------------------------------------
echo "  ✓ done. Opening Xcode…"
open WatchVoiceLLM.xcodeproj

cat <<'NEXT'

Next steps in Xcode:
  1. Select the "WatchVoiceLLM" scheme and your iPhone as the run destination.
  2. For each target (WatchVoiceLLM, WatchVoiceLLM-Watch):
     Signing & Capabilities → choose your Team. (Free Apple ID works; the
     on-device profile is valid for 7 days.)
  3. ⌘R to build & run. First launch: allow Microphone + Speech Recognition.
  4. To also run on Apple Watch, pick the Watch scheme (paired watch as
     destination) after the iPhone app is installed.

Default backend is the fast path: SFSpeechRecognizer (on-device JA) + Foundation
Models where available, falling back to Echo. To switch to WhisperKit + MLX/Qwen,
uncomment the package blocks in project.yml and re-run ./bootstrap.sh.
NEXT
