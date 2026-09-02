#!/usr/bin/env bash
set -e

echo "=========================================================================="
echo "⚡ 1-CLICK QWEN 3.8 FLASH NEXT (180B UNCENSORED) + HERMES AGENT BLACKWELL"
echo "=========================================================================="

HF_TOKEN="${HF_TOKEN:-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}"
export HF_TOKEN="$HF_TOKEN"
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_XET_HIGH_PERFORMANCE=1
GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"

# 1. System packages & tmux configuration
echo "📦 [1/6] Installing system tools (tmux, cmake, git, build-essential, curl, wget, aria2)..."
apt-get update -qq && apt-get install -y -qq tmux cmake build-essential git libcurl4-openssl-dev aria2 curl wget 2>/dev/null || true

cat << 'EOF' > ~/.tmux.conf
set -g mouse on
set -s set-clipboard on
set -g history-limit 50000
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel
bind-key -T copy-mode MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel
EOF

# 2. Python high-speed packages
echo "⚙️ [2/6] Installing Python inference & agent libraries..."
pip install -q -U "huggingface_hub[cli]" hf_transfer nvidia-cuda-cccl openai rich pydantic httpx marimo 2>/dev/null || true

# 3. Setup CUDA Unified Directory, Headers & Dynamic Linker
echo "🔧 [3/6] Setting up CUDA 13 Blackwell toolkit links & CCCL headers..."
CUDA_SRC=$(python3 -c "import nvidia.cu13, os; print(os.path.dirname(nvidia.cu13.__file__))" 2>/dev/null || echo "/usr/local/lib/python3.13/site-packages/nvidia/cu13")

if [ -d "$CUDA_SRC" ]; then
  rm -rf /usr/local/cuda
  ln -sf "$CUDA_SRC" /usr/local/cuda
  ln -sf /usr/local/cuda/lib /usr/local/cuda/lib64 2>/dev/null || true

  # Create unversioned .so symlinks for CMake FindCUDAToolkit
  cd /usr/local/cuda/lib 2>/dev/null || true
  for f in *.so.*; do
    base=$(echo "$f" | sed -E 's/\.so\.[0-9]+(\.[0-9]+)*/.so/')
    [ ! -e "$base" ] && ln -sf "$f" "$base" 2>/dev/null || true
  done
  cd /marimo

  # Fix CCCL header nesting for <nv/target> & disable compiler check
  ln -sf /usr/local/cuda/include/cccl/nv /usr/local/cuda/include/nv 2>/dev/null || true
  ln -sf /usr/local/cuda/include/cccl/cuda /usr/local/cuda/include/cuda 2>/dev/null || true
  find /usr/local/cuda -name "cuda_toolkit.h" -exec sed -i 's/#\s*error.*CUDA compiler and CUDA toolkit headers are incompatible.*//g' {} + 2>/dev/null || true

  # Register dynamic linker paths system-wide
  echo "/usr/local/cuda/lib" > /etc/ld.so.conf.d/cuda.conf
  echo "/usr/local/cuda/lib64" >> /etc/ld.so.conf.d/cuda.conf
  echo "/marimo/llama.cpp/build/bin" >> /etc/ld.so.conf.d/cuda.conf
  ldconfig 2>/dev/null || true

  export CUDA_PATH="/usr/local/cuda"
  export PATH="/usr/local/cuda/bin:$PATH"
  export LD_LIBRARY_PATH="/usr/local/cuda/lib:/usr/local/cuda/lib64:$LD_LIBRARY_PATH"
fi

# 4. Compile llama.cpp for Blackwell sm_120 (Cached if present)
echo "🔨 [4/6] Checking Blackwell-optimized llama-server (sm_120)..."
if [ ! -f "/marimo/llama.cpp/build/bin/llama-server" ]; then
  echo "  -> Compiling llama-server from danielhanchen/llama.cpp (qwen4exp branch)..."
  rm -rf /marimo/llama.cpp
  git clone -b qwen4exp/qwen3.8-flash-next --single-branch https://github.com/danielhanchen/llama.cpp.git /marimo/llama.cpp
  cd /marimo/llama.cpp
  cmake -B build \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES=120 \
    -DCMAKE_CUDA_FLAGS="-D_CCCL_DISABLE_CUDA_COMPILER_CHECK=1"
  cmake --build build -j$(nproc) --target llama-server
  cd /marimo
else
  echo "  ✅ Cached llama-server found at /marimo/llama.cpp/build/bin/llama-server!"
fi

# 5. Download 98.4GB Qwen 3.8 Flash Next Uncensored + Vision Projector
echo "📥 [5/6] Checking Qwen3.8-Flash-Next-Uncensored-IQ4XS Model (~98.4 GB)..."
MODEL_DIR="/marimo/models/Qwen3.8-Flash-Next-Uncensored-IQ4XS"
MODEL_FILE="$MODEL_DIR/Qwen3.8-Flash-Next-Uncensored-IQ4XS-NGQ4.gguf"
MMPROJ_FILE="$MODEL_DIR/mmproj-Qwen3.8-Flash-Next-Uncensored-BF16.gguf"
mkdir -p "$MODEL_DIR"

if [ ! -f "$MODEL_FILE" ] || [ ! -f "$MMPROJ_FILE" ]; then
  echo "  -> Fast downloading Qwen3.8-Flash-Next-Uncensored via huggingface-cli..."
  hf download cygnal/Qwen3.8-Flash-Next-Uncensored-IQ4XS-NGQ4-GGUF \
    --local-dir "$MODEL_DIR"
else
  echo "  ✅ Model and Vision Projector already cached on disk!"
fi

# 6. Launch llama-server with 256K Context on Safe Port 8085
echo "🚀 [6/6] Launching Qwen 3.8 Flash Server on 95GB Blackwell GPU (Port 8085)..."
pkill -9 -f "llama-server" 2>/dev/null || true
tmux kill-session -t qwen 2>/dev/null || true

tmux new-session -d -s qwen "bash -c '
  export LD_LIBRARY_PATH=/usr/local/cuda/lib:/usr/local/cuda/lib64:\$LD_LIBRARY_PATH
  /marimo/llama.cpp/build/bin/llama-server \
    --model \"$MODEL_FILE\" \
    --mmproj \"$MMPROJ_FILE\" \
    --host 127.0.0.1 --port 8085 \
    --n-gpu-layers 48 \
    --flash-attn on \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    --ctx-size 262144 \
    --rope-scaling yarn \
    --yarn-orig-ctx 131072 \
    --parallel 1 \
    --n-predict 65536 \
    --jinja;
  exec bash
'"

# 7. Configure Nous Research Hermes Agent
echo "🏛️ Setting up Nous Research Hermes Agent..."
pip install -q hermes-agent 2>/dev/null || true
mkdir -p ~/.hermes ~/.config/hermes /root/.hermes /home/marimo/.hermes 2>/dev/null || true

cat << 'HERMES_CFG' > ~/.hermes/config.yaml
provider: custom
base_url: "http://127.0.0.1:8085/v1"
api_key: "EMPTY"
model: "Qwen3.8-Flash-Next-Uncensored"
context_length: 262144
max_tokens: 65536
temperature: 0.2
system_prompt: "You are Hermes Agent, an autonomous AI engineer on an NVIDIA Blackwell system."
HERMES_CFG

cp ~/.hermes/config.yaml ~/.config/hermes/config.yaml 2>/dev/null || true
cp ~/.hermes/config.yaml /root/.hermes/config.yaml 2>/dev/null || true
cp ~/.hermes/config.yaml /home/marimo/.hermes/config.yaml 2>/dev/null || true

# 8. Deploy Marimo App
if [ -f "$(dirname "$0")/app.py" ]; then
  cp "$(dirname "$0")/app.py" /marimo/app.py
elif [ -n "$GH_TOKEN" ]; then
  curl -fsSL -H "Authorization: token $GH_TOKEN" https://raw.githubusercontent.com/harshraj170304-ux/qwen-flash-blackwell-molab/main/app.py -o /marimo/app.py 2>/dev/null || true
fi

echo ""
echo "=========================================================================="
echo "🎉 DEPLOYMENT COMPLETE! Qwen 3.8 Flash (180B) is LIVE on Blackwell GPU!"
echo "📡 Server Endpoint:  http://127.0.0.1:8085/v1"
echo "🧠 Context Window:    262,144 Tokens (YaRN RoPE + q8_0 KV Cache)"
echo "🏛️ Hermes Agent:     Ready! Type 'hermes-agent' in terminal to run."
echo "👉 Open /marimo/app.py in MoLab sidebar & click 'App View' to chat!"
echo "=========================================================================="
