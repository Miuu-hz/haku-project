"""
Haku A2A Simulator v3
- แต่ละ persona มี private Haku chat panel
- A2A Channel: autonomous multi-round discussion (AI คุยกันเอง)
- จบแล้ว → feedback กลับหาเจ้าของแต่ละ panel อัตโนมัติ
"""

import json
import re
import sys
from datetime import datetime
from pathlib import Path

import streamlit as st

sys.path.insert(0, str(Path(__file__).parent))

from persona import Persona, load_all_personas
from thaillm_client import ThaiLLMClient

PERSONAS_DIR = Path(__file__).parent / "personas"

# ─── Page config ──────────────────────────────────────────────────────────────
st.set_page_config(page_title="Haku A2A", page_icon="📡", layout="wide")

st.markdown("""
<style>
[data-testid="stChatMessage"] { padding: 4px 8px; }
.stButton > button { font-size: 13px; }
h3 { margin: 0 0 2px 0 !important; font-size: 16px !important; }
.round-divider { text-align:center; color:#555; font-size:11px;
                 border-top:1px solid #333; margin:6px 0; padding-top:4px; }
.feedback-box { background:#1a2f1a; border:1px solid #2d5a2d;
                border-radius:8px; padding:10px; margin:4px 0; }
</style>
""", unsafe_allow_html=True)

# ─── Session state ────────────────────────────────────────────────────────────
_DEFAULTS = {
    "all_personas": None,
    "active_personas": [],
    "persona_chats": {},
    "a2a_log": [],
    "a2a_summary": None,
    "session_started": False,
    "discussion_rounds": 3,
    "is_discussing": False,
}
for _k, _v in _DEFAULTS.items():
    if _k not in st.session_state:
        st.session_state[_k] = _v

if st.session_state.all_personas is None:
    st.session_state.all_personas = load_all_personas(PERSONAS_DIR)


def _now():
    return datetime.now().strftime("%H:%M")


def _client():
    return ThaiLLMClient(st.session_state.get("api_key", ""))


def _parse_think(text: str) -> tuple:
    """แยก <think>...</think> ออกจาก response หลัก
    รองรับทั้ง tag ปิดครบและ tag ที่ถูก truncate (token หมด)
    Returns: (main_content, think_content)
    """
    # กรณีปกติ: มีทั้ง <think> และ </think>
    match = re.search(r"<think>(.*?)</think>", text, re.DOTALL)
    if match:
        think = match.group(1).strip()
        main = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()
        return main, think

    # กรณี token หมดก่อน </think> — เอาทุกอย่างหลัง <think> เป็น think
    if "<think>" in text:
        parts = text.split("<think>", 1)
        main = parts[0].strip()
        think = parts[1].strip()
        return main, think

    return text.strip(), ""


# ─── LLM calls ────────────────────────────────────────────────────────────────

def call_haku(persona: Persona, user_msg: str) -> dict:
    """Returns {"content": str, "think": str}"""
    history = st.session_state.persona_chats.get(persona.filename, [])
    ctx = "\n".join(f"{m['role']}: {m['content']}" for m in history[-6:])
    system = persona.build_system_prompt(ctx)
    r = _client().chat(system, user_msg, max_tokens=350)
    raw = r.content if r.ok else f"⚠️ {r.error}"
    main, think = _parse_think(raw)
    return {"content": main, "think": think}


def _a2a_context(last_n: int = 30) -> str:
    return "\n".join(
        f"{m['from_avatar']} {m['from_name']}: {m['content']}"
        for m in st.session_state.a2a_log[-last_n:]
        if not m.get("is_divider")
    )


def _short_persona_info(persona: Persona) -> str:
    """ดึงเฉพาะ Identity lines จาก .md ไม่เกิน 250 chars"""
    lines = [
        l for l in persona.md_content.splitlines()
        if l.startswith("- ") or "Identity" in l or "อาชีพ" in l
    ]
    return "\n".join(lines)[:250]


def run_autonomous_discussion(starter: Persona, initial_message: str):
    """
    Directed turn-taking — คนละคนผลัดกันตอบ เหมือน LINE จริง:
      บอส → Dev → บอส → Dev → ... (max N turns)
    แต่ละ turn ส่ง "ได้รับข้อความจาก X: ..." ให้ responder
    จบด้วย feedback กลับหาเจ้าของทุก panel
    """
    active = st.session_state.active_personas
    others = [p for p in active if p.filename != starter.filename]
    if not others:
        st.session_state.is_discussing = False
        return

    max_turns = st.session_state.discussion_rounds * 2  # back-and-forth
    status = st.empty()
    prog = st.progress(0.0)

    last_speaker = starter
    last_message = initial_message
    other_idx = 0  # สำหรับ rotate ระหว่าง others หลายคน

    for turn in range(max_turns):
        # ── เลือก responder ──────────────────────────────────────────────────
        if last_speaker.filename == starter.filename:
            # starter พูดล่าสุด → others ตอบ (rotate ถ้ามีหลายคน)
            responder = others[other_idx % len(others)]
            other_idx += 1
        elif len(others) == 1:
            # มีแค่ 2 คน → starter ตอบกลับ
            responder = starter
        else:
            # others หลายคน → other คนถัดไปตอบ (ยัง ไม่กลับหา starter)
            responder = others[other_idx % len(others)]
            other_idx += 1

        status.info(f"💬 {responder.avatar} {responder.name} กำลังตอบ...")

        # ── Prompt สั้น เน้น 1 message ที่ต้องตอบ ────────────────────────────
        system = (
            f"คุณคือ {responder.name}\n"
            f"{_short_persona_info(responder)}\n\n"
            f"ได้รับข้อความจาก {last_speaker.name}: \"{last_message}\"\n"
            f"ตอบสั้น 1–2 ประโยค เหมือนส่ง LINE\n"
            f"ห้ามอธิบายยาว ห้าม bullet ห้ามพูดเรื่องอื่น\n"
            f"ถ้าบทสนทนาสรุปจบสมบูรณ์แล้ว ขึ้นต้นด้วย [DONE]"
        )
        r = _client().chat(
            system,
            f"{last_speaker.name}: {last_message}",
            max_tokens=120,
        )
        raw = r.content if r.ok else f"⚠️ {r.error}"
        main, think = _parse_think(raw)
        done = main.upper().startswith("[DONE]")
        reply = main.replace("[DONE]", "").replace("[done]", "").strip()

        if reply:
            st.session_state.a2a_log.append({
                "from_name": responder.name,
                "from_avatar": responder.avatar,
                "content": reply,
                "think": think,
                "ts": _now(),
            })

        last_speaker = responder
        last_message = reply or last_message
        prog.progress((turn + 1) / max_turns)

        if done or not reply:
            break

    # ── Auto-summary ──────────────────────────────────────────────────────────
    status.info("📋 สรุป...")
    st.session_state.a2a_summary = _generate_summary()

    # ── Feedback กลับหาเจ้าของ (ไม่มี think — ไม่ต้องการ reasoning) ──────────
    status.info("📬 ส่ง feedback...")
    full_log = _a2a_context(last_n=100)

    for persona in active:
        fb_system = (
            f"คุณคือ Haku ของ {persona.name}\n"
            f"สรุป chat ต่อไปนี้ให้ {persona.name} รู้ 3 ข้อ:\n"
            f"1. ตกลงอะไร  2. {persona.name} ต้องทำอะไร  3. deadline ถ้ามี\n"
            f"ภาษาไทย สั้น bullet"
        )
        r = _client().chat(fb_system, f"chat:\n{full_log[-600:]}", max_tokens=200)
        fb_main, _ = _parse_think(r.content if r.ok else "⚠️ ไม่สามารถสร้าง feedback")

        st.session_state.persona_chats.setdefault(persona.filename, []).append({
            "role": "assistant",
            "content": f"📬 **A2A สรุป:**\n\n{fb_main}",
            "ts": _now(),
            # ไม่มี think — feedback ไม่ควรแสดง reasoning
        })

    status.empty()
    prog.empty()
    st.session_state.is_discussing = False


def _generate_summary() -> dict:
    log_text = _a2a_context(last_n=100)
    names = [p.name for p in st.session_state.active_personas]
    system = (
        "คุณเป็น AI สรุปบทสนทนา ตอบเป็น JSON เท่านั้น ไม่มีข้อความอื่น\n\n"
        '{\n'
        '  "key_agreements": ["สิ่งที่ตกลงกัน"],\n'
        '  "unclear_items": ["สิ่งที่ยังไม่ชัด"],\n'
        '  "action_items": ["งานที่ต้องทำ"],\n'
        '  "calendar_events": ["event — วันที่"],\n'
        '  "tasks": ["คนรับผิดชอบ: งาน"],\n'
        '  "new_facts": { "<persona name>": ["fact ใหม่"] }\n'
        '}'
    )
    r = _client().chat(
        system,
        f"สรุปบทสนทนา:\n{log_text}\n\nPersonas: {', '.join(names)}",
        max_tokens=700,
    )
    if not r.ok:
        return {"error": r.error}
    text, _ = _parse_think(r.content)
    text = text.strip()
    if "```" in text:
        parts = text.split("```")
        text = parts[1][4:].strip() if parts[1].startswith("json") else parts[1].strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"raw_summary": r.content, "parse_error": True}


def update_persona_md(persona: Persona, facts: list):
    if not facts:
        return
    today = datetime.now().strftime("%Y-%m-%d %H:%M")
    block = f"\n\n## New Facts (A2A {today})\n" + "\n".join(f"- {f}" for f in facts)
    persona.md_content += block
    (PERSONAS_DIR / f"{persona.filename}.md").write_text(persona.md_content, encoding="utf-8")


# ─── Persona panel ────────────────────────────────────────────────────────────

def render_persona_panel(persona: Persona):
    p_id = persona.filename

    if p_id not in st.session_state.persona_chats:
        st.session_state.persona_chats[p_id] = []

    ctr_key = f"_ctr_{p_id}"
    if ctr_key not in st.session_state:
        st.session_state[ctr_key] = 0

    history = st.session_state.persona_chats[p_id]

    st.markdown(f"### {persona.avatar} {persona.name}")
    st.caption(f"Haku ส่วนตัว · `{p_id}.md`")

    # ── Chat history ──
    with st.container(height=320):
        if not history:
            st.caption("ยังไม่มีการสนทนา — พิมพ์แล้วกด ส่ง ↓")
        for i, msg in enumerate(history[-12:]):
            is_last = i == len(history[-12:]) - 1
            if msg["role"] == "user":
                with st.chat_message("user"):
                    st.write(msg["content"])
            else:
                with st.chat_message("assistant", avatar=persona.avatar):
                    st.write(msg["content"])
                    if msg.get("think"):
                        with st.expander("💭 reasoning", expanded=False):
                            st.caption(msg["think"])
                    # ปุ่ม "📡 ส่งไป A2A" ใต้ reply ล่าสุด (ไม่ใช่ feedback)
                    if is_last and msg.get("origin") and not st.session_state.is_discussing:
                        if st.button(
                            "📡 ส่งไป A2A → Auto-discuss",
                            key=f"fwd_{p_id}_{len(history)}",
                            type="primary",
                        ):
                            original = msg["origin"]
                            st.session_state.a2a_log.append({
                                "from_name": persona.name,
                                "from_avatar": persona.avatar,
                                "content": original,
                                "ts": _now(),
                            })
                            st.session_state.is_discussing = True
                            run_autonomous_discussion(persona, original)
                            st.rerun()

    # ── Input ──
    input_key = f"input_{p_id}_{st.session_state[ctr_key]}"
    user_input = st.text_input(
        "msg",
        placeholder="พิมพ์ข้อความ... Haku ช่วยร่าง → ส่ง A2A",
        key=input_key,
        label_visibility="collapsed",
        disabled=st.session_state.is_discussing,
    )
    send_btn = st.button(
        "ส่ง 🤖",
        key=f"send_{p_id}",
        use_container_width=True,
        type="primary",
        disabled=st.session_state.is_discussing,
    )

    if send_btn and user_input.strip():
        txt = user_input.strip()
        history.append({"role": "user", "content": txt, "ts": _now()})
        with st.spinner("Haku กำลังคิด..."):
            result = call_haku(persona, txt)
        history.append({
            "role": "assistant",
            "content": result["content"],
            "think": result["think"],
            "ts": _now(),
            "origin": txt,
        })
        st.session_state[ctr_key] += 1
        st.rerun()

    # ── fact_memory.md ──
    with st.expander("📄 fact_memory.md", expanded=False):
        st.text(persona.md_content)


# ─── A2A panel ────────────────────────────────────────────────────────────────

def render_a2a_panel():
    st.markdown("### 📡 A2A Channel")
    st.caption("Autonomous discussion · AI คุยกันเองหลาย rounds")

    log = st.session_state.a2a_log

    # ── Log display ──
    with st.container(height=340):
        if not log:
            st.caption("ยังว่างอยู่ — กด '📡 ส่งไป A2A' ในแต่ละ panel เพื่อเริ่ม")
        for msg in log:
            if msg.get("is_divider"):
                st.markdown(
                    f'<div class="round-divider">── {msg["from_name"]} ──</div>',
                    unsafe_allow_html=True,
                )
            else:
                with st.chat_message("assistant", avatar=msg["from_avatar"]):
                    st.markdown(f"**{msg['from_name']}** `{msg['ts']}`")
                    st.write(msg["content"])
                    if msg.get("think"):
                        with st.expander("💭 reasoning", expanded=False):
                            st.caption(msg["think"])

    st.divider()

    # ── Manual summary (ถ้ายังไม่มี auto-summary) ──
    if not st.session_state.a2a_summary and len(log) >= 2:
        if st.button("📋 สรุปบทสนทนา", use_container_width=True,
                     disabled=st.session_state.is_discussing):
            with st.spinner("สรุป..."):
                st.session_state.a2a_summary = _generate_summary()
            st.rerun()

    # ── Summary display ──
    if st.session_state.a2a_summary:
        _render_summary(st.session_state.a2a_summary)


def _render_summary(s: dict):
    if s.get("error"):
        st.error(s["error"])
        return
    if s.get("parse_error"):
        st.info(s.get("raw_summary", ""))
        return

    st.markdown("---")
    st.markdown("#### 📋 สรุป")

    for item in s.get("key_agreements", []):
        st.markdown(f"- ✅ {item}")
    for item in s.get("unclear_items", []):
        st.markdown(f"- ⚠️ {item}")
    for item in s.get("action_items", []):
        st.markdown(f"- 📌 {item}")

    events = s.get("calendar_events", [])
    tasks = s.get("tasks", [])
    if events or tasks:
        st.markdown("---")
        st.markdown("#### 🗓️ Worker Actions")
        for e in events:
            st.markdown(f"📅 {e}")
        for t in tasks:
            st.markdown(f"✏️ {t}")
        if st.button("✅ บันทึก Workers", key="save_workers"):
            st.success("บันทึกแล้ว ✓")

    new_facts = s.get("new_facts", {})
    if new_facts:
        st.markdown("---")
        st.markdown("#### 🧠 Facts ใหม่")
        has = False
        for p in st.session_state.active_personas:
            facts = new_facts.get(p.name, [])
            if facts:
                has = True
                st.markdown(f"{p.avatar} **{p.name}:** " + " · ".join(f"`{f}`" for f in facts))
        if has and st.button("💾 บันทึก Memory", key="save_memory"):
            for p in st.session_state.active_personas:
                update_persona_md(p, new_facts.get(p.name, []))
            st.success("อัปเดต .md แล้ว ✓")
            st.rerun()


# ─── Sidebar ──────────────────────────────────────────────────────────────────
with st.sidebar:
    st.markdown("## 📡 Haku A2A")
    st.divider()

    st.text_input("🔑 ThaiLLM API Key", type="password",
                  placeholder="sk-...", key="api_key")
    if not st.session_state.get("api_key"):
        st.warning("ใส่ API key ก่อนเริ่ม")

    st.divider()
    st.markdown("### 👥 Personas (2–4)")
    selected = []
    for p in st.session_state.all_personas:
        if st.checkbox(f"{p.avatar} {p.name}", value=True, key=f"chk_{p.filename}"):
            selected.append(p)

    st.divider()
    st.markdown("### ⚙️ Discussion")
    st.session_state.discussion_rounds = st.slider(
        "จำนวน rounds", min_value=1, max_value=6,
        value=st.session_state.discussion_rounds,
        help="AI แต่ละตัวจะคุยกัน N รอบก่อนสรุป"
    )

    st.divider()
    uploaded = st.file_uploader("📁 เพิ่ม Persona (.md)", type=["md"])
    if uploaded:
        content = uploaded.read().decode("utf-8")
        first_line = content.splitlines()[0] if content else ""
        name = (first_line.replace("# Persona:", "").strip()
                if "Persona:" in first_line else Path(uploaded.name).stem)
        stem = Path(uploaded.name).stem
        if stem not in [p.filename for p in st.session_state.all_personas]:
            st.session_state.all_personas.append(
                Persona(name=name, avatar="🆕", md_content=content, filename=stem)
            )
            st.rerun()

    st.divider()
    c1, c2 = st.columns(2)
    with c1:
        start_btn = st.button("▶ เริ่ม", type="primary", use_container_width=True)
    with c2:
        reset_btn = st.button("🗑 ล้าง", use_container_width=True)

    if start_btn:
        if len(selected) < 2:
            st.error("เลือกอย่างน้อย 2 personas")
        elif not st.session_state.get("api_key"):
            st.error("ต้องมี API key")
        else:
            st.session_state.active_personas = selected
            st.session_state.persona_chats = {p.filename: [] for p in selected}
            st.session_state.a2a_log = []
            st.session_state.a2a_summary = None
            st.session_state.is_discussing = False
            st.session_state.session_started = True
            st.rerun()

    if reset_btn:
        st.session_state.a2a_log = []
        st.session_state.a2a_summary = None
        st.session_state.is_discussing = False
        st.session_state.persona_chats = {
            p.filename: [] for p in st.session_state.active_personas
        }
        st.rerun()

    if st.session_state.session_started:
        st.divider()
        st.caption(f"Personas: {len(st.session_state.active_personas)}")
        st.caption(f"A2A messages: {len(st.session_state.a2a_log)}")
        if st.session_state.is_discussing:
            st.warning("🔄 Discussion กำลังรัน...")


# ─── Main layout ──────────────────────────────────────────────────────────────
if not st.session_state.session_started:
    st.title("📡 Haku A2A Simulator")
    st.markdown(
        "**Flow:** พิมพ์ → Haku ร่าง → 📡 ส่ง A2A → AI คุยกันเองหลาย rounds → "
        "📬 feedback กลับหาเจ้าของทุกคน"
    )
    st.info("เลือก personas (2–4) และกด **▶ เริ่ม** ใน sidebar")
    all_p = st.session_state.all_personas
    if all_p:
        cards = st.columns(min(len(all_p), 4))
        for i, p in enumerate(all_p[:4]):
            with cards[i]:
                st.markdown(f"### {p.avatar} {p.name}")
                lines = [l for l in p.md_content.splitlines() if l.startswith("- ")][:4]
                st.markdown("\n".join(lines) or "_ไม่มี facts_")
    st.stop()

# ─── Session layout ───────────────────────────────────────────────────────────
active = st.session_state.active_personas
n = len(active)
left_personas = active[: n // 2]
right_personas = active[n // 2 :]

widths = [1.0] * len(left_personas) + [1.3] + [1.0] * len(right_personas)
cols = st.columns(widths, gap="small")

for i, persona in enumerate(left_personas):
    with cols[i]:
        render_persona_panel(persona)

with cols[len(left_personas)]:
    render_a2a_panel()

for i, persona in enumerate(right_personas):
    with cols[len(left_personas) + 1 + i]:
        render_persona_panel(persona)
