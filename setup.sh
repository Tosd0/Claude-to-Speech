#!/bin/bash
# Claude-to-Speech Setup Script

set -e

echo "================================================"
echo "   Claude-to-Speech Setup"
echo "================================================"
echo ""

# Check if we're in the right directory
if [ ! -f "requirements.txt" ] || [ ! -d "server" ]; then
    echo "❌ Error: Please run this script from the claude-to-speech directory"
    exit 1
fi

# Step 1: Create virtual environment if it doesn't exist.
# The Stop hook looks in .venv/ first, then venv/, so either works.
VENV_DIR=".venv"
if [ -d "venv" ] && [ ! -d "$VENV_DIR" ]; then
    VENV_DIR="venv"
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "🐍 Creating Python virtual environment in $VENV_DIR ..."
    python3 -m venv "$VENV_DIR"
    echo "✅ Virtual environment created"
else
    echo "✅ Virtual environment already exists ($VENV_DIR)"
fi
echo ""

echo "📦 Installing Python dependencies..."
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install -r requirements.txt
echo "✅ Dependencies installed"
echo ""

# Step 2: Bootstrap .env from the template and optionally fill in the key.
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo "✅ Created .env from .env.example"
fi

if grep -qE '^ELEVENLABS_API_KEY=your_api_key_here' .env; then
    read -r -p "Enter your ElevenLabs API key (leave blank to edit .env later): " api_key
    if [ -n "$api_key" ]; then
        # Escape forward slashes and ampersands for sed
        escaped=$(printf '%s\n' "$api_key" | sed -e 's/[\/&]/\\&/g')
        sed -i.bak "s/^ELEVENLABS_API_KEY=.*/ELEVENLABS_API_KEY=$escaped/" .env
        rm -f .env.bak
        echo "✅ API key saved to .env"
    else
        echo "ℹ️  Edit .env and set ELEVENLABS_API_KEY before starting the server."
    fi
else
    echo "✅ .env already has a non-placeholder ELEVENLABS_API_KEY"
fi
echo ""

# Step 3: Make hooks executable
echo "🔨 Making hooks executable..."
chmod +x hooks/stop.sh
echo "✅ Hooks configured"
echo ""

# Step 4: Sanity-check the config
echo "🧪 Testing server configuration..."
if python3 -c "import sys; sys.path.insert(0, 'server'); from config.tts_config import ELEVENLABS_API_KEY; print('✅ Config loads successfully')" 2>/dev/null; then
    echo "✅ Configuration validated"
else
    echo "⚠️  Configuration validation failed - check .env"
fi
echo ""

echo "================================================"
echo "   Setup Complete!"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Activate the virtual environment:"
echo "   source $VENV_DIR/bin/activate"
echo ""
echo "2. Start the TTS server:"
echo "   python3 server/tts_server.py"
echo ""
echo "3. In Claude Code, run:"
echo "   /speak"
echo ""
echo "For troubleshooting, see INSTALL.md"
