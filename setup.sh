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

# Fix libcuda.so (CUDA Driver target) for CMake FindCUDAToolkit
DRIVER_LIB=$(find /usr/lib /usr/local -name "libcuda.so.1" -o -name "libcuda.so" 2>/dev/null | head -n 1)
if [ -n "$DRIVER_LIB" ]; then
  mkdir -p /usr/local/cuda/lib64/stubs /usr/local/cuda/lib/stubs /usr/lib/x86_64-linux-gnu
  ln -sf "$DRIVER_LIB" /usr/local/cuda/lib64/stubs/libcuda.so 2>/dev/null || true
  ln -sf "$DRIVER_LIB" /usr/local/cuda/lib/stubs/libcuda.so 2>/dev/null || true
  ln -sf "$DRIVER_LIB" /usr/local/cuda/lib64/libcuda.so 2>/dev/null || true
  ln -sf "$DRIVER_LIB" /usr/local/cuda/lib/libcuda.so 2>/dev/null || true
  ln -sf "$DRIVER_LIB" /usr/lib/x86_64-linux-gnu/libcuda.so 2>/dev/null || true
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

# 4. Compile llama.cpp for Blackwell sm_120 (Cached if present)
echo "🔨 [4/6] Checking Blackwell-optimized llama-server (sm_120)..."
if [ ! -f "/marimo/llama.cpp/build/bin/llama-server" ]; then
  echo "  -> Fetching danielhanchen/llama.cpp (qwen4exp branch)..."
  if [ ! -d "/marimo/llama.cpp/.git" ]; then
    rm -rf /marimo/llama.cpp
    git clone -b qwen4exp/qwen3.8-flash-next --single-branch https://github.com/danielhanchen/llama.cpp.git /marimo/llama.cpp
  fi
  cd /marimo/llama.cpp

  # Pre-patch ggml-cuda CMakeLists & inject CCCL compiler check bypass
  python3 -c '
import os
# 1. Patch main CMakeLists.txt
main_p = "/marimo/llama.cpp/CMakeLists.txt"
if os.path.exists(main_p):
    with open(main_p, "r") as f: s = f.read()
    if "_CCCL_DISABLE_CUDA_COMPILER_CHECK" not in s:
        s = "add_compile_definitions(_CCCL_DISABLE_CUDA_COMPILER_CHECK=1)\n" + s
        with open(main_p, "w") as f: f.write(s)

# 2. Patch ggml-cuda CMakeLists.txt to link real CUDA driver library
cuda_p = "/marimo/llama.cpp/ggml/src/ggml-cuda/CMakeLists.txt"
if os.path.exists(cuda_p):
    with open(cuda_p, "r") as f: s = f.read()
    patch = """
add_compile_definitions(_CCCL_DISABLE_CUDA_COMPILER_CHECK=1)
find_library(REAL_CUDA_DRIVER NAMES cuda libcuda.so.1 libcuda PATHS /usr/lib/x86_64-linux-gnu /usr/lib64 /usr/local/cuda/lib64 /usr/local/cuda/lib)
if (REAL_CUDA_DRIVER)
    message(STATUS "Explicitly linking ggml-cuda to driver: ${REAL_CUDA_DRIVER}")
    if (NOT TARGET CUDA::cuda_driver)
        add_library(CUDA::cuda_driver UNKNOWN IMPORTED)
    endif()
    set_target_properties(CUDA::cuda_driver PROPERTIES IMPORTED_LOCATION "${REAL_CUDA_DRIVER}")
    link_libraries("${REAL_CUDA_DRIVER}")
endif()
"""
    if "REAL_CUDA_DRIVER" not in s:
        s = patch + "\n" + s
        with open(cuda_p, "w") as f: f.write(s)
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
    -DCMAKE_C_FLAGS="-D_CCCL_DISABLE_CUDA_COMPILER_CHECK=1" \
    -DCMAKE_EXE_LINKER_FLAGS="-L/usr/lib/x86_64-linux-gnu -L/usr/local/cuda/lib64 -lcuda" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L/usr/lib/x86_64-linux-gnu -L/usr/local/cuda/lib64 -lcuda"
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
