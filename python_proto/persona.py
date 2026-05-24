from dataclasses import dataclass, field
from pathlib import Path

# avatar ตามชื่อไฟล์ (fallback = 🤖)
_AVATAR_MAP = {
    "boss": "👔",
    "engineer": "💻",
    "designer": "🎨",
    "haku_user": "🧠",
}


@dataclass
class Persona:
    name: str
    avatar: str
    md_content: str
    filename: str = ""

    def build_system_prompt(self, conversation_context: str) -> str:
        ctx_section = (
            f"\n=== บทสนทนาที่ผ่านมา ===\n{conversation_context}"
            if conversation_context.strip()
            else ""
        )
        return (
            f"คุณคือ {self.name}\n\n"
            f"=== ข้อมูลความจำของคุณ ===\n{self.md_content}\n\n"
            f"=== กฎการตอบ ===\n"
            f"- ตอบในฐานะ {self.name} เท่านั้น อย่าออกนอกบทบาท\n"
            f"- ใช้ข้อมูลจากความจำข้างต้นเป็น context หลัก\n"
            f"- ตอบกระชับ 1–3 ประโยค (ยกเว้นถูกถามให้อธิบาย)\n"
            f"- ห้ามบอกว่าตัวเองเป็น AI"
            f"{ctx_section}"
        )


def load_persona_from_file(path: Path) -> Persona:
    md_content = path.read_text(encoding="utf-8")
    # ดึง "# Persona: ชื่อ" จากบรรทัดแรก
    first_line = md_content.splitlines()[0] if md_content else ""
    name = first_line.replace("# Persona:", "").strip() if "Persona:" in first_line else path.stem
    avatar = _AVATAR_MAP.get(path.stem, "🤖")
    return Persona(name=name, avatar=avatar, md_content=md_content, filename=path.stem)


def load_all_personas(personas_dir: Path) -> list[Persona]:
    personas = []
    for md_file in sorted(personas_dir.glob("*.md")):
        personas.append(load_persona_from_file(md_file))
    return personas


def reload_persona(persona: Persona, personas_dir: Path) -> Persona:
    """อ่าน .md ใหม่จากไฟล์ (หลัง update memory)"""
    path = personas_dir / f"{persona.filename}.md"
    if path.exists():
        persona.md_content = path.read_text(encoding="utf-8")
    return persona
