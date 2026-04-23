#!/bin/bash
#
# Claude Code Stop Hook - Automatic TTS
# Fires after Claude finishes responding
# Extracts and speaks TTS markers from response
#

# Debug logging (set DEBUG=1 in .env to enable)
DEBUG="${DEBUG:-1}"
DEBUG_FILE="/tmp/claude_stop_hook.log"

# Get the plugin directory (parent of hooks directory)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Path to claude_speak.py and venv python
SPEAK_SCRIPT="$PLUGIN_DIR/scripts/claude_speak.py"
VENV_PYTHON="$PLUGIN_DIR/.venv/bin/python3"
# Fall back to system python3 if venv doesn't exist
[ ! -x "$VENV_PYTHON" ] && VENV_PYTHON="python3"

# Debug path resolution
[ "$DEBUG" = "1" ] && echo "SCRIPT_DIR: $SCRIPT_DIR" >> "$DEBUG_FILE"
[ "$DEBUG" = "1" ] && echo "PLUGIN_DIR: $PLUGIN_DIR" >> "$DEBUG_FILE"
[ "$DEBUG" = "1" ] && echo "SPEAK_SCRIPT: $SPEAK_SCRIPT" >> "$DEBUG_FILE"

# Read the JSON input from stdin
INPUT=$(cat)

# Debug the raw input
[ "$DEBUG" = "1" ] && echo "=== Stop Hook Fired at $(date) ===" >> "$DEBUG_FILE"
[ "$DEBUG" = "1" ] && echo "Raw input: $INPUT" >> "$DEBUG_FILE"

# Extract last_assistant_message directly from the hook input JSON
RESPONSE=$(echo "$INPUT" | "$VENV_PYTHON" -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('last_assistant_message', ''))
except:
    pass
" 2>/dev/null || echo "")

[ "$DEBUG" = "1" ] && echo "Extracted response length: ${#RESPONSE} chars" >> "$DEBUG_FILE"
[ "$DEBUG" = "1" ] && echo "First 200 chars: ${RESPONSE:0:200}" >> "$DEBUG_FILE"

if [ -n "$RESPONSE" ]; then
    : # continue processing

    # Prevent duplicate execution using hash check (macOS compatible)
    LOCK_FILE="/tmp/claude_tts_hook.lock"
    HASH_FILE="/tmp/claude_tts_hook.hash"
    RESPONSE_HASH=$(echo "$RESPONSE" | md5 -r 2>/dev/null | cut -d' ' -f1 || echo "$RESPONSE" | md5sum 2>/dev/null | cut -d' ' -f1)

    # Use mkdir for atomic locking (works on macOS and Linux)
    if ! mkdir "$LOCK_FILE.d" 2>/dev/null; then
        [ "$DEBUG" = "1" ] && echo "Another hook instance is processing, skipping" >> "$DEBUG_FILE"
        exit 0
    fi
    trap 'rmdir "$LOCK_FILE.d" 2>/dev/null' EXIT

    # Check if we already processed this exact message
    LAST_HASH=$(cat "$HASH_FILE" 2>/dev/null || echo "")
    if [ "$RESPONSE_HASH" = "$LAST_HASH" ]; then
        [ "$DEBUG" = "1" ] && echo "Duplicate message detected (same content hash), skipping" >> "$DEBUG_FILE"
        exit 0
    fi

    echo "$RESPONSE_HASH" > "$HASH_FILE"
else
    [ "$DEBUG" = "1" ] && echo "Empty response, nothing to process" >> "$DEBUG_FILE"
    exit 0
fi

# Check if response explicitly marks SILENT (handle both escaped and unescaped)
if echo "$RESPONSE" | grep -qE "(<\\!--|<!--) TTS: SILENT (-->|-->)"; then
    # Explicitly marked as silent - do nothing
    [ "$DEBUG" = "1" ] && echo "Found SILENT marker, skipping TTS" >> "$DEBUG_FILE"
    exit 0
fi

# Extract TTS text if present (handle both escaped and unescaped markers)
TTS_TEXT=$(echo "$RESPONSE" | sed -n 's/.*<\\!-- TTS: "\([^"]*\)".*/\1/p' | head -1)
[ "$DEBUG" = "1" ] && echo "Escaped pattern result: '$TTS_TEXT'" >> "$DEBUG_FILE"

if [ -z "$TTS_TEXT" ]; then
    # Try unescaped version as fallback
    TTS_TEXT=$(echo "$RESPONSE" | sed -n 's/.*<!-- TTS: "\([^"]*\)".*/\1/p' | head -1)
    [ "$DEBUG" = "1" ] && echo "Unescaped pattern result: '$TTS_TEXT'" >> "$DEBUG_FILE"
fi

# If we found TTS text, speak it
if [ -n "$TTS_TEXT" ]; then
    [ "$DEBUG" = "1" ] && echo "Extracted TTS text: $TTS_TEXT" >> "$DEBUG_FILE"

    # Check if speak script exists and is executable
    if [ -x "$SPEAK_SCRIPT" ]; then
        # Call the speak script with the extracted text
        "$VENV_PYTHON" "$SPEAK_SCRIPT" --conversation "$TTS_TEXT" 2>&1 | while IFS= read -r line; do
            [ "$DEBUG" = "1" ] && echo "TTS output: $line" >> "$DEBUG_FILE"
        done
    else
        [ "$DEBUG" = "1" ] && echo "ERROR: $SPEAK_SCRIPT not found or not executable" >> "$DEBUG_FILE"
    fi
else
    # No TTS marker found - silent by default
    [ "$DEBUG" = "1" ] && echo "No TTS marker found, defaulting to silent" >> "$DEBUG_FILE"
fi

exit 0