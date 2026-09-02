import marimo

__generated_with = "0.11.0"
app = marimo.App(width="medium")


@app.cell
def __():
    import marimo as mo
    import urllib.request, json, time, os, base64

    # Preset System Prompts
    PRESETS = {
        "🧠 Deep Reasoning & Engineering (CoT)": (
            "You are Qwen 3.8 Flash Next, an exceptionally powerful, deeply analytical AI reasoning and engineering system running on an NVIDIA Blackwell GPU. "
            "Think rigorously and deeply before answering. Wrap your detailed reasoning process in <think>...</think> tags, then provide the optimal, complete solution."
        ),
        "💻 High-Precision Full-Stack Coder": (
            "You are an elite principal software architect and full-stack engineer. "
            "Write production-grade, bug-free, well-typed, and complete code without shortcuts or placeholders. Explain key design decisions clearly."
        ),
        "🔓 Raw Uncensored Creative & Literature": (
            "You are an uncensored, deeply expressive creative writer, philosopher, and story architect. "
            "Provide vivid, visceral, authentic, and unrestricted narratives with immense literary depth and evocative imagery."
        ),
        "🏛️ Hermes Autonomous Agent Persona": (
            "You are Hermes Agent v0.20.6, an autonomous, highly capable AI engineer with persistent memory, tool proficiency, and multi-step execution capabilities on Blackwell."
        ),
        "🎯 Custom Persona": ""
    }

    # UI Controls: System Prompt & Presets
    preset_dropdown = mo.ui.dropdown(
        options=list(PRESETS.keys()),
        value="🧠 Deep Reasoning & Engineering (CoT)",
        label="🎭 Personality & Architecture Preset:"
    )

    system_prompt_box = mo.ui.text_area(
        value=PRESETS["🧠 Deep Reasoning & Engineering (CoT)"],
        label="⚙️ System Prompt:",
        rows=4
    )

    # Sliders & Generation Parameters
    temp_slider = mo.ui.slider(start=0.0, stop=1.5, step=0.05, value=0.2, label="🌡️ Temperature:")
    top_p_slider = mo.ui.slider(start=0.1, stop=1.0, step=0.05, value=0.9, label="🎯 Top-P:")
    max_tokens_slider = mo.ui.slider(start=1024, stop=65536, step=1024, value=8192, label="📝 Max Output Tokens:")
    repeat_penalty = mo.ui.slider(start=1.0, stop=1.5, step=0.02, value=1.05, label="🔁 Repeat Penalty:")

    # Multimodal Vision Upload
    image_uploader = mo.ui.file(
        filetypes=[".png", ".jpg", ".jpeg", ".webp"],
        label="📸 (Optional) Attach Image for Multimodal Vision Analysis (mmproj):"
    )

    # Session Management
    session_restore_file = mo.ui.file(
        filetypes=[".json"],
        label="📂 Restore Chat Session (.json):",
        kind="button"
    )

    clear_chat_btn = mo.ui.run_button(label="🗑️ Clear Conversation", kind="danger")

    # Message Input & Send Button
    user_input = mo.ui.text_area(
        placeholder="Ask Qwen 3.8 Flash anything — coding, complex architecture, deep reasoning, literature, or vision analysis...",
        label="💬 Your Message to Qwen 3.8 Flash (180B):",
        rows=4
    )
    send_btn = mo.ui.run_button(label="🚀 Send to Qwen 3.8 Flash (95GB Blackwell)")

    # Layout Assembly
    controls_accordion = mo.accordion({
        "⚙️ Model Parameters & Presets": mo.vstack([
            preset_dropdown,
            system_prompt_box,
            mo.hstack([temp_slider, top_p_slider]),
            mo.hstack([max_tokens_slider, repeat_penalty]),
            mo.hstack([image_uploader, session_restore_file, clear_chat_btn])
        ])
    })

    ui_header = mo.vstack([
        mo.md("""
        # ⚡ Qwen 3.8 Flash Next (180B Uncensored) & Hermes Agent Studio
        **NVIDIA RTX PRO 6000 Blackwell (95.6 GB VRAM)** | **256,144 Context Window (YaRN)** | **Native Vision Projector**
        """),
        controls_accordion,
        mo.md("---"),
        user_input,
        send_btn
    ])

    return (
        mo, urllib, json, time, os, base64, PRESETS,
        preset_dropdown, system_prompt_box,
        temp_slider, top_p_slider, max_tokens_slider, repeat_penalty,
        image_uploader, session_restore_file, clear_chat_btn,
        user_input, send_btn, ui_header
    )


@app.cell
def __(
    mo, urllib, json, time, os, base64, PRESETS,
    preset_dropdown, system_prompt_box,
    temp_slider, top_p_slider, max_tokens_slider, repeat_penalty,
    image_uploader, session_restore_file, clear_chat_btn,
    user_input, send_btn, ui_header
):
    # Persistent Conversation State
    get_messages, set_messages = mo.state([])

    # 1. Update system prompt on preset change
    current_system_prompt = system_prompt_box.value
    if preset_dropdown.value != "🎯 Custom Persona" and PRESETS.get(preset_dropdown.value):
        current_system_prompt = PRESETS[preset_dropdown.value]

    # 2. Clear chat handler
    if clear_chat_btn.value:
        set_messages([])

    # 3. Restore chat from JSON
    if session_restore_file.value:
        try:
            raw_data = session_restore_file.value[0].contents
            restored = json.loads(raw_data.decode("utf-8"))
            if isinstance(restored, list):
                set_messages(restored)
        except Exception:
            pass

    history = list(get_messages())
    status_msg = ""

    # 4. Check Health of llama-server (Port 8085)
    server_online = False
    try:
        req = urllib.request.Request("http://127.0.0.1:8085/health")
        with urllib.request.urlopen(req, timeout=1.5) as r:
            server_online = (r.status == 200)
    except Exception:
        server_online = False

    server_badge = "🟢 **Server Online (Port 8085)**" if server_online else "🔴 **Server Starting or Offline** *(Check `tmux a -t qwen` in terminal)*"

    # 5. Handle Send Event
    if send_btn.value and user_input.value.strip():
        text_content = user_input.value.strip()

        # Handle Image attachment
        has_image = False
        img_b64 = ""
        if image_uploader.value:
            for item in image_uploader.value:
                b = getattr(item, "contents", None) or (item.get("contents") if isinstance(item, dict) else None)
                if b:
                    img_b64 = base64.b64encode(b).decode("utf-8")
                    has_image = True
                    break

        if has_image:
            user_payload = [
                {"type": "text", "text": text_content},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{img_b64}"}}
            ]
        else:
            user_payload = text_content

        history.append({"role": "user", "content": user_payload})
        set_messages(history)

        # Build OpenAI-Compatible Payload
        api_messages = [{"role": "system", "content": current_system_prompt}]
        for m in history:
            api_messages.append({"role": m["role"], "content": m["content"]})

        payload = {
            "messages": api_messages,
            "temperature": float(temp_slider.value),
            "top_p": float(top_p_slider.value),
            "max_tokens": int(max_tokens_slider.value),
            "repeat_penalty": float(repeat_penalty.value),
            "stream": False
        }

        try:
            t0 = time.time()
            data = json.dumps(payload).encode("utf-8")
            req = urllib.request.Request(
                "http://127.0.0.1:8085/v1/chat/completions",
                data=data,
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=300) as resp:
                res_obj = json.loads(resp.read().decode("utf-8"))
                elapsed = time.time() - t0

                choice = res_obj["choices"][0]["message"]
                assistant_reply = choice.get("content", "")
                usage = res_obj.get("usage", {})
                completion_tokens = usage.get("completion_tokens", 0)
                speed = completion_tokens / elapsed if elapsed > 0 else 0

                history.append({"role": "assistant", "content": assistant_reply})
                set_messages(history)
                status_msg = f"⚡ *Generated {completion_tokens} tokens in {elapsed:.2f}s ({speed:.2f} tokens/sec on Blackwell)*"
        except urllib.error.HTTPError as e:
            err = e.read().decode("utf-8", errors="ignore")
            history.append({"role": "assistant", "content": f"⚠️ **Server Error:** `{err}`"})
            set_messages(history)
        except Exception as e:
            history.append({"role": "assistant", "content": f"⚠️ **Connection Error:** `{e}`"})
            set_messages(history)

    # 6. Render Messages with Reasoning Callouts
    rendered_convo = []
    for msg in history:
        role = msg["role"]
        raw_c = msg["content"]

        if role == "user":
            if isinstance(raw_c, list):
                txt = next((x["text"] for x in raw_c if x["type"] == "text"), "")
                rendered_convo.append(mo.md(f"🧑 **You:** *(with attached image)*\n\n{txt}"))
            else:
                rendered_convo.append(mo.md(f"🧑 **You:**\n\n{raw_c}"))
        elif role == "assistant":
            # Extract <think> reasoning tags
            if "<think>" in raw_c and "</think>" in raw_c:
                think_part = raw_c.split("<think>")[1].split("</think>")[0].strip()
                answer_part = raw_c.split("</think>")[1].strip()
                rendered_convo.append(mo.vstack([
                    mo.accordion({"🧠 Deep Reasoning Chain (<think>)": mo.md(f"```markdown\n{think_part}\n```")}),
                    mo.md(f"🤖 **Qwen 3.8 Flash:**\n\n{answer_part}")
                ]))
            else:
                rendered_convo.append(mo.md(f"🤖 **Qwen 3.8 Flash:**\n\n{raw_c}"))

    # Export button
    export_download = mo.download(
        data=json.dumps(history, indent=2),
        filename="qwen_session.json",
        label="💾 Export Chat Session (.json)"
    )

    full_view = mo.vstack([
        ui_header,
        mo.hstack([mo.md(server_badge), export_download]),
        mo.md(status_msg) if status_msg else mo.md(""),
        mo.md("---"),
        mo.md("### 💬 Active Conversation:"),
        mo.vstack(rendered_convo) if rendered_convo else mo.md("*(No messages yet. Ask a question above!)*")
    ])

    return full_view


if __name__ == "__main__":
    app.run()
