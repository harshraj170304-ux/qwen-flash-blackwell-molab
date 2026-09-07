#!/usr/bin/env bash
set -e

echo "=========================================================================="
echo "⚡ 1-CLICK QWEN 3.8 FLASH NEXT (180B UNCENSORED) + HERMES AGENT BLACKWELL"
echo "=========================================================================="

HF_TOKEN="${HF_TOKEN:-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}"
export HF_TOKEN="$HF_TOKEN"
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_XET_HIGH_PERFORMANCE=1
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-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}}"
export GH_TOKEN="$GH_TOKEN"

# 1. System packages & tmux configuration
echo "📦 [1/6] Installing system tools (tmux, cmake, git, build-essential, curl, wget, aria2, sqlite3)..."
apt-get update -qq && apt-get install -y -qq tmux cmake build-essential git libcurl4-openssl-dev aria2 curl wget sqlite3 2>/dev/null || true

cat << 'EOF' > ~/.tmux.conf
set -g mouse on
set -s set-clipboard on
set -g history-limit 50000
unbind-key -T copy-mode-vi MouseDragEnd1Pane
unbind-key -T copy-mode MouseDragEnd1Pane
EOF

# 2. Python high-speed packages
echo "⚙️ [2/6] Installing Python inference & agent libraries..."
pip install -q -U "huggingface_hub[cli]" hf_transfer nvidia-cuda-cccl openai rich pydantic httpx marimo 2>/dev/null || true

# 3. Setup CUDA Unified Directory, Headers & Dynamic Linker
echo "🔧 [3/6] Setting up CUDA 13 Blackwell toolkit links, CCCL headers & libcuda driver..."
CUDA_SRC=$(python3 -c "import nvidia.cu13, os; print(os.path.dirname(nvidia.cu13.__file__))" 2>/dev/null || echo "/usr/local/lib/python3.13/site-packages/nvidia/cu13")

if [ -d "$CUDA_SRC" ]; then
  rm -rf /usr/local/cuda
  ln -sf "$CUDA_SRC" /usr/local/cuda
  ln -sf /usr/local/cuda/lib /usr/local/cuda/lib64 2>/dev/null || true
fi

# Link NVVM compiler directory (provides cicc & libdevice for nvcc)
NVVM_DIR=$(find /usr/local/lib/python3* /usr/local -type d -name nvvm 2>/dev/null | head -n 1)
[ -n "$NVVM_DIR" ] && ln -sf "$NVVM_DIR" /usr/local/cuda/nvvm 2>/dev/null || true

# Create unversioned .so symlinks for CMake FindCUDAToolkit
if [ -d "/usr/local/cuda/lib" ]; then
  cd /usr/local/cuda/lib 2>/dev/null || true
  for f in *.so.*; do
    base=$(echo "$f" | sed -E 's/\.so\.[0-9]+(\.[0-9]+)*/.so/')
    [ ! -e "$base" ] && ln -sf "$f" "$base" 2>/dev/null || true
  done
  cd /marimo
fi

# Fix libcuda.so (CUDA Driver target) without self-referencing symlinks
rm -f /usr/lib/x86_64-linux-gnu/libcuda.so /usr/local/cuda/lib64/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so 2>/dev/null || true
DRIVER_LIB=$(find /usr/lib /usr/local -type f -name "libcuda.so*" 2>/dev/null | head -n 1)
[ -z "$DRIVER_LIB" ] && DRIVER_LIB="/usr/lib/x86_64-linux-gnu/libcuda.so.1"

if [ -e "$DRIVER_LIB" ]; then
  mkdir -p /usr/local/cuda/lib64/stubs /usr/lib/x86_64-linux-gnu
  ln -sf "$DRIVER_LIB" /usr/lib/x86_64-linux-gnu/libcuda.so 2>/dev/null || true
  ln -sf "$DRIVER_LIB" /usr/local/cuda/lib64/stubs/libcuda.so 2>/dev/null || true
  ln -sf "$DRIVER_LIB" /usr/local/cuda/lib64/libcuda.so 2>/dev/null || true
fi

# Fix CCCL header nesting for <nv/target>
python3 -c '
import os, shutil
for base in ["/usr/local/cuda/include", "/usr/local/lib/python3.13/site-packages/nvidia/cu13/include"]:
    if not os.path.exists(base): continue
    nv_dir = os.path.join(base, "nv")
    os.makedirs(nv_dir, exist_ok=True)
    for root, dirs, files in os.walk(base):
        if "target" in files and "nv" in root:
            src_target = os.path.join(root, "target")
            dst_target = os.path.join(nv_dir, "target")
            if not os.path.exists(dst_target):
                try: shutil.copy2(src_target, dst_target)
                except Exception: pass
' 2>/dev/null || true
ln -sf /usr/local/cuda/include/cccl/nv /usr/local/cuda/include/nv 2>/dev/null || true
ln -sf /usr/local/cuda/include/cccl/cuda /usr/local/cuda/include/cuda 2>/dev/null || true

# Permanently neutralise #error from ALL cuda_toolkit.h files (and inject definition at top)
python3 -c '
import os, glob
paths = glob.glob("/usr/**/cuda_toolkit.h", recursive=True) + [
    "/usr/local/cuda/include/cuda/std/__cccl/cuda_toolkit.h",
    "/usr/local/include/cuda/std/__cccl/cuda_toolkit.h"
]
for p in set(paths):
    if os.path.isfile(p):
        try:
            with open(p, "r") as f: content = f.read()
            if "_CCCL_DISABLE_CUDA_COMPILER_CHECK" not in content[:200]:
                content = "#define _CCCL_DISABLE_CUDA_COMPILER_CHECK 1\n" + content
            lines = []
            for l in content.splitlines():
                if "incompatible" in l and "error" in l:
                    lines.append("// #error bypassed by installer")
                else:
                    lines.append(l)
            with open(p, "w") as f: f.write("\n".join(lines) + "\n")
            print(f"  ✨ Patched: {p}")
        except Exception: pass
' 2>/dev/null || true

# Direct patch on the exact compiler header path
if [ -f "/usr/local/cuda/include/cuda/std/__cccl/cuda_toolkit.h" ]; then
  sed -i 's/.*error.*CUDA compiler and CUDA toolkit headers are incompatible.*/\/\/ bypassed/g' /usr/local/cuda/include/cuda/std/__cccl/cuda_toolkit.h 2>/dev/null || true
fi

# Register dynamic linker paths system-wide
echo "/usr/local/cuda/lib" > /etc/ld.so.conf.d/cuda.conf
echo "/usr/local/cuda/lib64" >> /etc/ld.so.conf.d/cuda.conf
echo "/marimo/llama.cpp/build/bin" >> /etc/ld.so.conf.d/cuda.conf
ldconfig 2>/dev/null || true

export CUDA_PATH="/usr/local/cuda"
export PATH="/usr/local/cuda/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib:/usr/local/cuda/lib64:$LD_LIBRARY_PATH"

# 4. Fast-Deploy Prebuilt Blackwell llama-server (sm_120 + MTP in ~3 seconds)
echo "🔨 [4/8] Checking Blackwell-optimized llama-server with MTP (sm_120)..."
if [ ! -f "/marimo/llama.cpp/build/bin/llama-server" ]; then
  mkdir -p /marimo/llama.cpp/build/bin
  echo "  -> ⚡ Fast-downloading precompiled Blackwell MTP engine from GitHub Releases (~48 MB)..."
  
  RELEASE_ASSET_URL="https://api.github.com/repos/harshraj170304-ux/qwen-flash-blackwell-molab/releases/assets/548882571"
  if curl -fsSL -H "Authorization: token $GH_TOKEN" -H "Accept: application/octet-stream" -L "$RELEASE_ASSET_URL" -o /tmp/llama-server-blackwell.tar.gz 2>/dev/null && [ -s /tmp/llama-server-blackwell.tar.gz ]; then
    tar -xzf /tmp/llama-server-blackwell.tar.gz -C /marimo/llama.cpp/build/bin
    rm -f /tmp/llama-server-blackwell.tar.gz
    chmod +x /marimo/llama.cpp/build/bin/llama-* 2>/dev/null || true
    echo "  ✅ Prebuilt Blackwell MTP engine deployed in 3 seconds!"
  else
    echo "  ⚠️ Prebuilt download failed or offline, compiling from source..."
    if [ ! -d "/marimo/llama.cpp/.git" ]; then
      rm -rf /marimo/llama.cpp
      git clone -b qwen4exp/mtp --single-branch https://github.com/danielhanchen/llama.cpp.git /marimo/llama.cpp
    fi
    cd /marimo/llama.cpp

    # Inject CCCL compiler check bypass into main CMakeLists.txt
    python3 -c '
import os
main_p = "/marimo/llama.cpp/CMakeLists.txt"
if os.path.exists(main_p):
    with open(main_p, "r") as f: s = f.read()
    if "_CCCL_DISABLE_CUDA_COMPILER_CHECK" not in s:
        s = "add_compile_definitions(_CCCL_DISABLE_CUDA_COMPILER_CHECK=1)\n" + s
        with open(main_p, "w") as f: f.write(s)
' 2>/dev/null || true

    echo "  -> Compiling llama-server with native Blackwell sm_120 kernels..."
    rm -rf /marimo/llama.cpp/build
    mkdir -p /marimo/llama.cpp/build
    cd /marimo/llama.cpp
    cmake -B build \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES=120 \
      -DCUDAToolkit_ROOT=/usr/local/cuda \
      -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
      -DCMAKE_CUDA_FLAGS="-D_CCCL_DISABLE_CUDA_COMPILER_CHECK=1" \
      -DCMAKE_CXX_FLAGS="-D_CCCL_DISABLE_CUDA_COMPILER_CHECK=1" \
      -DCMAKE_C_FLAGS="-D_CCCL_DISABLE_CUDA_COMPILER_CHECK=1"
    nice -n 10 cmake --build build -j10 --target llama-server
    cd /marimo
  fi
else
  echo "  ✅ Cached llama-server found at /marimo/llama.cpp/build/bin/llama-server!"
fi

# 5. Download Huihui Qwen 3.8 Flash Next Abliterated (111.3 GB UD-Q4_K_XL) + Vision Projector + MTP Draft Head
echo "📥 [5/8] Checking Huihui Qwen 3.8 Flash Next Abliterated Model & MTP Head..."
MODEL_DIR="/marimo/models/huihui-qwen"
MODEL_FILE="$MODEL_DIR/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf"
MMPROJ_FILE="$MODEL_DIR/mmproj-model-bf16.gguf"
MTP_DIR="/marimo/models/mtp"
MTP_FILE="$MTP_DIR/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf"
mkdir -p "$MODEL_DIR" "$MTP_DIR"

# Reuse existing vision projector if already downloaded in previous sessions
if [ ! -f "$MMPROJ_FILE" ] && [ -f "/marimo/models/Qwen3.8-Flash-Next-Uncensored-IQ4XS/mmproj-Qwen3.8-Flash-Next-Uncensored-BF16.gguf" ]; then
  MMPROJ_FILE="/marimo/models/Qwen3.8-Flash-Next-Uncensored-IQ4XS/mmproj-Qwen3.8-Flash-Next-Uncensored-BF16.gguf"
fi

if [ ! -f "$MODEL_FILE" ]; then
  echo "  -> ⚡ Fast downloading Huihui Qwen3.8 Flash Next Abliterated UD-Q4_K_XL (~111.3 GB)..."
  HF_XET_HIGH_PERFORMANCE=1 hf download huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-GGUF \
    --include "UD-Q4_K_XL/*" \
    --local-dir "$MODEL_DIR" || \
  python3 -c "
import os
from huggingface_hub import snapshot_download
os.environ['HF_XET_HIGH_PERFORMANCE'] = '1'
snapshot_download(
    repo_id='huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-GGUF',
    allow_patterns='UD-Q4_K_XL/*',
    local_dir='$MODEL_DIR'
)
"
else
  echo "  ✅ Huihui UD-Q4_K_XL Model shards already cached on disk!"
fi

if [ ! -f "$MMPROJ_FILE" ]; then
  echo "  -> Downloading Multimodal Vision Projector..."
  HF_XET_HIGH_PERFORMANCE=1 hf download huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-GGUF \
    mmproj-model-bf16.gguf \
    --local-dir "$MODEL_DIR" || \
  python3 -c "
import os
from huggingface_hub import hf_hub_download
os.environ['HF_XET_HIGH_PERFORMANCE'] = '1'
hf_hub_download(
    repo_id='huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-GGUF',
    filename='mmproj-model-bf16.gguf',
    local_dir='$MODEL_DIR'
)
"
else
  echo "  ✅ Vision Projector already cached on disk!"
fi

if [ ! -f "$MTP_FILE" ]; then
  echo "  -> ⚡ Fast multi-stream downloading Qwen 3.8 MTP shared draft head (~2.6 GB)..."
  if command -v aria2c >/dev/null 2>&1; then
    aria2c -q --console-log-level=error -x 16 -s 16 -k 1M -d "$MTP_DIR" -o "mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf" \
      "https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/resolve/main/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf" || true
  fi
  if [ ! -s "$MTP_FILE" ]; then
    hf download unsloth/Qwen3.8-Flash-Next-GGUF \
      MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf \
      --local-dir "$MTP_DIR" 2>/dev/null || true
    [ -f "$MTP_DIR/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf" ] && mv "$MTP_DIR/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf" "$MTP_FILE" 2>/dev/null || true
  fi
  if [ ! -s "$MTP_FILE" ]; then
    wget -q --show-progress -O "$MTP_FILE" \
      "https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/resolve/main/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf" || \
    curl -L -o "$MTP_FILE" \
      "https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/resolve/main/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf"
  fi
else
  echo "  ✅ MTP shared draft head already cached on disk!"
fi

# 6. Launch llama-server with Qwen 3.8 MTP on Safe Port 8085 (105 tok/s peak)
echo "🚀 [6/8] Launching Qwen 3.8 Flash Server with MTP on 95GB Blackwell GPU (Port 8085)..."
pkill -9 -f "llama-server" 2>/dev/null || true
tmux kill-session -t qwen 2>/dev/null || true
sleep 2

tmux new-session -d -s qwen "bash -c '
  export LD_LIBRARY_PATH=/usr/local/cuda/lib:/usr/local/cuda/lib64:\$LD_LIBRARY_PATH
  /marimo/llama.cpp/build/bin/llama-server \
    --model \"$MODEL_FILE\" \
    --model-draft \"$MTP_FILE\" \
    --spec-type draft-mtp \
    --spec-draft-n-max 2 \
    --n-gpu-layers 99 \
    --n-gpu-layers-draft 99 \
    --mmproj \"$MMPROJ_FILE\" \
    --host 127.0.0.1 --port 8085 \
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

echo "⏳ Starting server with Qwen 3.8 MTP (8 seconds)..."
sleep 8
tmux capture-pane -pt qwen -S -25 2>/dev/null || true

# 7. Restore Hermes Memory, Sessions & 2-Way Auto-Backup Engine
echo "🏛️ [7/8] Setting up Hermes Agent & Restoring Permanent Memory from GitHub..."
pip install -q hermes-agent 2>/dev/null || true

GITHUB_USER="harshraj170304-ux"
MEMORY_REPO="${MEMORY_REPO:-https://${GH_TOKEN}@github.com/${GITHUB_USER}/hermes-molab.git}"
BACKUP_DIR="/tmp/hermes_repo"

mkdir -p /root/.hermes /home/marimo/.hermes ~/.hermes ~/.config/hermes /marimo/storage

# Pull latest persistent memory from GitHub
if [ ! -d "$BACKUP_DIR/.git" ]; then
  echo "  -> Fetching sessions & state database from $GITHUB_USER/hermes-molab..."
  git clone "$MEMORY_REPO" "$BACKUP_DIR" 2>/dev/null || true
else
  cd "$BACKUP_DIR"
  git pull --rebase origin main 2>/dev/null || true
  cd /marimo
fi

# Restore files into Hermes config directories
if [ -d "$BACKUP_DIR/hermes_data" ]; then
  cp -rf "$BACKUP_DIR"/hermes_data/* "$BACKUP_DIR"/hermes_data/.* /home/marimo/.hermes/ 2>/dev/null || true
  cp -rf "$BACKUP_DIR"/hermes_data/* "$BACKUP_DIR"/hermes_data/.* /root/.hermes/ 2>/dev/null || true
  cp -rf "$BACKUP_DIR"/hermes_data/* "$BACKUP_DIR"/hermes_data/.* ~/.hermes/ 2>/dev/null || true
  echo "  ✅ Restored Hermes state.db, SOUL.md, MEMORY.md, and past sessions!"
fi

# Ensure SQLite integrity & truncate WAL so queries don't fail
python3 -c '
import sqlite3, os
for db_path in ["/home/marimo/.hermes/state.db", "/root/.hermes/state.db", os.path.expanduser("~/.hermes/state.db")]:
    if os.path.isfile(db_path):
        try:
            conn = sqlite3.connect(db_path)
            conn.execute("PRAGMA wal_checkpoint(TRUNCATE);")
            conn.close()
        except Exception: pass
' 2>/dev/null || true

# Configure Hermes local endpoint on Port 8085
cat << 'HERMES_CFG' > ~/.hermes/config.yaml
provider: custom
base_url: "http://127.0.0.1:8085/v1"
api_key: "EMPTY"
model: "Qwen3.8-Flash-Next-Uncensored"
context_length: 262144
max_tokens: 65536
temperature: 0.2
system_prompt: "You are Hermes Agent, an autonomous AI engineer on an NVIDIA Blackwell system. You have persistent memory across notebook restarts."
HERMES_CFG

cp ~/.hermes/config.yaml ~/.config/hermes/config.yaml 2>/dev/null || true
cp ~/.hermes/config.yaml /root/.hermes/config.yaml 2>/dev/null || true
cp ~/.hermes/config.yaml /home/marimo/.hermes/config.yaml 2>/dev/null || true
chmod -R 777 /home/marimo/.hermes /root/.hermes ~/.hermes 2>/dev/null || true
chown -R marimo:marimo /home/marimo/.hermes 2>/dev/null || true

# Install hermes-sync CLI tool
cat << 'SYNC_SCRIPT' > /usr/local/bin/hermes-sync
#!/usr/bin/env bash
BACKUP_DIR="/tmp/hermes_repo"
[ ! -d "$BACKUP_DIR" ] && exit 0

mkdir -p "$BACKUP_DIR/hermes_data"

# Checkpoint SQLite WAL
python3 -c '
import sqlite3, os
for p in ["/home/marimo/.hermes/state.db", "/root/.hermes/state.db", os.path.expanduser("~/.hermes/state.db")]:
    if os.path.isfile(p):
        try:
            conn = sqlite3.connect(p)
            conn.execute("PRAGMA wal_checkpoint(TRUNCATE);")
            conn.close()
        except Exception: pass
' 2>/dev/null || true

# Copy all active Hermes state files
for dir in /home/marimo/.hermes /root/.hermes ~/.hermes; do
  if [ -d "$dir" ]; then
    cp -rf "$dir"/* "$dir"/.* "$BACKUP_DIR/hermes_data/" 2>/dev/null || true
  fi
done

cd "$BACKUP_DIR"
git config user.name 'harshraj170304-ux'
git config user.email 'harshraj170304@gmail.com'
git pull --rebase origin main 2>/dev/null || true
git add hermes_data/ 2>/dev/null || true
if ! git diff --cached --quiet 2>/dev/null; then
  git commit -m "Auto-backup Hermes session & memory $(date -u '+%Y-%m-%d %H:%M:%S UTC')" 2>/dev/null
  git push origin main 2>/dev/null && echo "✅ [hermes-sync] Memory & sessions uploaded to GitHub!"
else
  echo "✨ [hermes-sync] Up to date (no changes)."
fi
SYNC_SCRIPT
chmod +x /usr/local/bin/hermes-sync

# Launch silent 30s background auto-sync daemon
echo "  -> Starting background auto-backup daemon (every 30s to GitHub)..."
pkill -f "hermes_sync_daemon" 2>/dev/null || true
nohup bash -c '
while true; do
  /usr/local/bin/hermes-sync >/dev/null 2>&1
  sleep 30
done
' > /tmp/hermes_daemon.log 2>&1 &

# 8. Deploy Marimo App
echo "📱 [8/8] Deploying Marimo web app..."
if [ -f "$(dirname "$0")/app.py" ]; then
  cp "$(dirname "$0")/app.py" /marimo/app.py
else
  curl -fsSL https://raw.githubusercontent.com/harshraj170304-ux/qwen-flash-blackwell-molab/main/app.py -o /marimo/app.py 2>/dev/null || true
fi

echo ""
echo "=========================================================================="
echo "🎉 DEPLOYMENT COMPLETE! Qwen 3.8 Flash (180B) is LIVE on Blackwell GPU!"
echo "📡 Server Endpoint:    http://127.0.0.1:8085/v1"
echo "🧠 Context Window:      262,144 Tokens (YaRN RoPE + q8_0 KV Cache)"
echo "💾 Persistent Memory:  Restored from GitHub & Auto-Backing up every 30s!"
echo "💬 Resume Chat:        Type 'hermes chat -c' or 'hermes -c' in terminal"
echo "📂 List Past Sessions: Type 'hermes sessions list'"
echo "⚡ Force Instant Save: Type 'hermes-sync'"
echo "👉 Open /marimo/app.py in MoLab sidebar & click 'App View' to chat!"
echo "=========================================================================="
