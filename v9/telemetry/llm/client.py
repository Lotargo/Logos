"""
LLM client — ChatOpenAI via zen opencode (OpenAI-compatible endpoint).
"""
import os
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".env"))
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from langchain_openai import ChatOpenAI


def get_llm(temperature: float = 0.1) -> ChatOpenAI:
    """Return configured ChatOpenAI pointing at zen opencode."""
    api_key = os.getenv("OPENCODE_API_KEY")
    model = os.getenv("model", "mimo-v2.5-free")

    if not api_key:
        raise ValueError(
            "OPENCODE_API_KEY not found in .env. "
            "Set it in the project root .env file."
        )

    return ChatOpenAI(
        model=model,
        api_key=api_key,
        base_url="https://opencode.ai/zen/v1",
        temperature=temperature,
        max_tokens=4096,
        default_headers={"X-Provider": "opencode"},
    )
