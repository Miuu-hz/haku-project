import requests
from dataclasses import dataclass


@dataclass
class LLMResponse:
    content: str
    total_tokens: int
    ok: bool
    error: str = ""


class ThaiLLMClient:
    BASE_URL = "http://thaillm.or.th/api/v1/chat/completions"
    MODEL = "openthaigpt-thaillm-8b-instruct-v7.2"
    TIMEOUT = 30

    def __init__(self, api_key: str):
        self.api_key = api_key

    def chat(
        self,
        system_prompt: str,
        user_message: str,
        max_tokens: int = 400,
    ) -> LLMResponse:
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        body = {
            "model": self.MODEL,
            "max_tokens": max_tokens,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
        }
        try:
            resp = requests.post(
                self.BASE_URL, json=body, headers=headers, timeout=self.TIMEOUT
            )
            if resp.status_code == 429:
                return LLMResponse("", 0, False, "Rate limit (429) — รอสักครู่แล้วลองใหม่")
            if resp.status_code == 401:
                return LLMResponse("", 0, False, "API key ไม่ถูกต้อง (401)")
            resp.raise_for_status()
            data = resp.json()
            content = data["choices"][0]["message"]["content"].strip()
            tokens = data.get("usage", {}).get("total_tokens", 0)
            return LLMResponse(content, tokens, True)
        except requests.Timeout:
            return LLMResponse("", 0, False, "Timeout — server ไม่ตอบใน 30 วินาที")
        except Exception as e:
            return LLMResponse("", 0, False, str(e))
