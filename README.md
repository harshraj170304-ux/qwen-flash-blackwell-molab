# ⚡ Qwen 3.8 Flash Next (180B Uncensored) + Hermes Agent on Blackwell MoLab

> **1-Click Deployment for NVIDIA RTX PRO 6000 Blackwell GPU (95.6 GB VRAM)** with **262,144 Context Window (YaRN)**, **Multimodal Vision Projector**, and **Nous Research Hermes Agent**.

---

## 🚀 1-Click Deployment Command

Paste this command into your container terminal:

```bash
curl -fsSL -H "Authorization: token $GH_TOKEN" https://raw.githubusercontent.com/harshraj170304-ux/qwen-flash-blackwell-molab/main/setup.sh | bash
```

*(If using a public repository, you can simply run: `curl -fsSL https://raw.githubusercontent.com/harshraj170304-ux/qwen-flash-blackwell-molab/main/setup.sh | bash`)*

---

## 🖥️ What this 1-Click Script does automatically:

1. 📦 **Installs System Tools**: `tmux`, `cmake`, `git`, `build-essential`, `aria2`, `curl`, `wget`, with mouse scrolling pre-configured.
2. 🔧 **Configures Blackwell CUDA 13**: Links CCCL headers (`<nv/target>`), creates unversioned `.so` symlinks, and sets up system `ldconfig`.
3. 🔨 **Compiles Blackwell-optimized llama-server (`sm_120`)**: Automatically compiles `danielhanchen/llama.cpp` (`qwen4exp` branch) for native Blackwell architecture.
4. 📥 **Downloads Model & Vision Projector (~98.4 GB)**: Uses high-speed HF transfer to download `cygnal/Qwen3.8-Flash-Next-Uncensored-IQ4XS-NGQ4-GGUF` and `mmproj-Qwen3.8-Flash-Next-Uncensored-BF16.gguf`.
5. 🚀 **Launches Server on Safe Port 8085**: Starts `llama-server` in background `tmux` (`qwen`) with full **256K context (`262,144` tokens)**, YaRN RoPE scaling, and `q8_0` KV cache.
6. 🏛️ **Installs & Configures Hermes Agent**: Configures `~/.hermes/config.yaml` to point to the local 256K endpoint.
7. 🎨 **Deploys Interactive Marimo Studio**: Copies `app.py` to `/marimo/app.py` for visual chatting, parameter tuning, reasoning chain inspection, and vision uploads.

---

## 🎮 How to Use:

### Option A: Interactive In-Browser Studio (Marimo)
1. Open `/marimo/app.py` in the MoLab file explorer.
2. Switch to **App View**.
3. Chat, upload images, inspect `<think>` reasoning chains, or adjust temperature/tokens!

### Option B: Autonomous Hermes Agent CLI
Run in your container terminal:
```bash
hermes-agent
```

### Option C: Check Server Logs
```bash
tmux a -t qwen
```
*(Press `Ctrl+B` then `D` to detach)*
