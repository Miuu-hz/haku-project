from dataclasses import dataclass, field
from datetime import datetime
from persona import Persona


@dataclass
class ChatMessage:
    sender: str        # persona name หรือ "คุณ"
    avatar: str        # emoji
    content: str
    timestamp: str = field(default_factory=lambda: datetime.now().strftime("%H:%M"))
    is_human: bool = False
    token_count: int = 0


class GroupChat:
    def __init__(self, personas: list[Persona]):
        self.personas: list[Persona] = personas
        self.history: list[ChatMessage] = []

    def add_human_message(self, text: str) -> ChatMessage:
        msg = ChatMessage(sender="คุณ", avatar="🧑", content=text, is_human=True)
        self.history.append(msg)
        return msg

    def add_persona_message(self, persona: Persona, content: str, tokens: int = 0) -> ChatMessage:
        msg = ChatMessage(
            sender=persona.name,
            avatar=persona.avatar,
            content=content,
            token_count=tokens,
        )
        self.history.append(msg)
        return msg

    def format_context(self, last_n: int = 10) -> str:
        """สร้าง conversation string สำหรับใส่ใน system prompt"""
        recent = self.history[-last_n:] if len(self.history) > last_n else self.history
        lines = []
        for m in recent:
            lines.append(f"{m.avatar} {m.sender} [{m.timestamp}]: {m.content}")
        return "\n".join(lines)

    def get_responding_personas(self, _message: str) -> list[Persona]:
        """Phase 1: ทุก persona ตอบทุกข้อความ"""
        return self.personas

    def clear(self) -> None:
        self.history.clear()
