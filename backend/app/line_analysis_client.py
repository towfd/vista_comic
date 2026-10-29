"""The Claude call behind a line analysis, called by the line-analysis worker.

Same seam as ``comprehension_client``: an ``anthropic.Anthropic`` client built
fresh per call from ``config.get_claude_api_key()`` (never hardcoded, never
logged) by ``_client()``, which tests replace with a stub.

Three decisions worth knowing before changing anything here, all from
`.scratch/web-line-analysis/spec.md`:

**Structured output, not a forced tool.** The three models the reader picks
from reject a forced ``tool_choice``, so the answer's shape is pinned with
``output_config.format`` and a JSON schema instead. The answer arrives as the
text of the final message and is parsed here.

**The translation is final.** The line arrives with a translation the reader
has already reviewed, and the model explains the Vietnamese against it rather
than translating again -- the prompt says so, and nothing in the schema asks
for a translation.

**Streaming, with refusal fallback.** A long Fable call can outlast the SDK's
HTTP timeout on a plain request, so the call streams and collects the final
message. ``fallbacks: "default"`` lets the API re-run a declined request on
another model inside the same call; a ``refusal`` that survives it is reported
as ``Refused``.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Sequence, Union

import anthropic

from .config import get_claude_api_key
from .normalization import normalized_key

#: What the reader picks, mapped to the model ID sent. The client never sends a
#: model ID itself, so retiring one is a change here and nowhere else.
MODEL_IDS = {
    "sonnet": "claude-sonnet-5-5",
    "opus": "claude-opus-5-5",
    "fable": "claude-fable-5-1",
}

# Adaptive thinking spends from the same budget as the answer, so this leaves
# room for both. A starting value; ticket 02 measures real calls and tunes it.
_MAX_OUTPUT_TOKENS = 8000

# Per-read ceiling, not per-call: the call streams, so this bounds a stalled
# stream rather than a long answer.
_REQUEST_TIMEOUT_SECONDS = 120.0

_FALLBACK_BETA = "server-side-fallback-2026-07-01"

PARTS_OF_SPEECH = (
    "名詞", "動詞", "形容詞", "副詞", "代名詞", "介詞", "連詞", "助詞",
    "語氣詞", "數詞", "量詞", "感嘆詞", "狀聲詞", "人名", "地名", "片語",
)

SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "words": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "text": {"type": "string"},
                    "meaning": {"type": "string"},
                    "partOfSpeech": {"type": "string", "enum": list(PARTS_OF_SPEECH)},
                    "hanViet": {"type": "string"},
                    "note": {"type": "string"},
                },
                "required": ["text", "meaning", "partOfSpeech", "hanViet", "note"],
                "additionalProperties": False,
            },
        },
        "grammar": {"type": "string"},
        "tone": {"type": "string"},
    },
    "required": ["words", "grammar", "tone"],
    "additionalProperties": False,
}

_WORD_FIELDS = SCHEMA["properties"]["words"]["items"]["required"]

# Agreed word for word in grilling; change it with ticket 02's comparison in hand.
SYSTEM_PROMPT = """\
You are a Vietnamese tutor for a reader in Taiwan who is learning Vietnamese by reading Korean webtoons in Vietnamese translation. Write every explanation in Traditional Chinese as used in Taiwan.

You get one speech-bubble line in Vietnamese and its reviewed Traditional Chinese translation. The translation is final: do not retranslate, correct it, or offer alternatives. Explain the Vietnamese so the reader can see how it becomes that translation.

Split the line into words, not syllables. Vietnamese puts a space between every syllable, so a multi-syllable word (thanh toán, viện phí) is one unit, and a fixed expression that carries one meaning stays together. A name from the name table is one unit, glossed with its official name.

Cover every unit in reading order, including pronouns, particles and sentence-final words (à, nhé, đi) — those are where a learner gets lost.

For each unit: text exactly as written in the line; meaning in this line, worded to match the given translation; partOfSpeech from the list; hanViet — the Traditional Chinese characters if it is a Sino-Vietnamese word (viện phí → 院費), empty if it is not or you are not sure (only give characters when every syllable is Sino-Vietnamese and you know the standard characters; native words such as có, yêu, mới, mùa stay empty); note — one short sentence only when it helps (who a pronoun points to and the relationship or attitude it shows, a particle's nuance, why the translation words it this way), otherwise empty.

Then grammar: 2–4 sentences on how the line is built, referring to the units; and tone: 1–2 sentences on emotion, register and politeness."""


@dataclass(frozen=True)
class Name:
    """One name-table entry the reader sent with the line."""

    source: str
    target: str


class Refused:
    """The call ended in a refusal that the fallback did not rescue."""


REFUSED = Refused()


class InvalidAnalysis(Exception):
    """Claude answered, but not with something usable as an analysis."""


def _client() -> anthropic.Anthropic:
    """Construct a fresh Anthropic client; tests monkeypatch this."""
    return anthropic.Anthropic(
        api_key=get_claude_api_key(), timeout=_REQUEST_TIMEOUT_SECONDS
    )


def user_message(source_text: str, translation: str, names: Sequence[Name]) -> str:
    """The line, its translation, and the names in it -- and nothing else (no image)."""
    table = "\n".join(f"{n.source} = {n.target}" for n in names) or "(none)"
    return (
        f"<names>\n{table}\n</names>\n\n"
        f"<line>\n{source_text}\n</line>\n\n"
        f"<translation>\n{translation}\n</translation>"
    )


def build_request(
    *, model: str, source_text: str, translation: str, names: Sequence[Name]
) -> dict[str, Any]:
    """The keyword arguments for one streamed call. Raises ``KeyError`` on an unknown model."""
    return {
        "model": MODEL_IDS[model],
        "max_tokens": _MAX_OUTPUT_TOKENS,
        "system": SYSTEM_PROMPT,
        "thinking": {"type": "adaptive"},
        "output_config": {"format": {"type": "json_schema", "schema": SCHEMA}},
        "messages": [
            {"role": "user", "content": user_message(source_text, translation, names)}
        ],
        "betas": [_FALLBACK_BETA],
        "fallbacks": "default",
    }


def _answer_text(message: Any) -> str:
    """The answer's text: what follows the last fallback switch, if there was one.

    A model that declines mid-answer leaves its partial text in the content
    before the ``fallback`` block; only what the rescuing model wrote after it
    is the answer.
    """
    parts: list[str] = []
    for block in message.content:
        kind = getattr(block, "type", None)
        if kind == "fallback":
            parts = []
        elif kind == "text":
            parts.append(block.text)
    return "".join(parts)


def analyse(
    *, model: str, source_text: str, translation: str, names: Sequence[Name]
) -> Union[dict[str, Any], Refused]:
    """Call Claude for one line; the parsed answer, or ``REFUSED``.

    Raises ``InvalidAnalysis`` when the answer is cut off or is not JSON. Any
    SDK error propagates to the worker, which records it as ``error``.
    """
    request = build_request(
        model=model, source_text=source_text, translation=translation, names=names
    )
    with _client().beta.messages.stream(**request) as stream:
        message = stream.get_final_message()

    if message.stop_reason == "refusal":
        return REFUSED
    if message.stop_reason == "max_tokens":
        raise InvalidAnalysis("answer cut off at max_tokens")
    try:
        return json.loads(_answer_text(message))
    except ValueError as error:
        raise InvalidAnalysis(f"answer is not JSON: {error}") from error


def is_usable(result: Any, source_text: str) -> bool:
    """Whether a parsed answer can be shown: the right shape, at least one word,
    and every word actually in the line (ignoring case and spacing).

    The schema already pins the shape; checking it again costs nothing and keeps
    a malformed row from reaching the reader. The in-the-line check is what the
    schema cannot express -- a model that "corrects" a word, or glosses one the
    line does not contain, is caught here.
    """
    if not isinstance(result, dict):
        return False
    words = result.get("words")
    if not isinstance(words, list) or not words:
        return False
    if not isinstance(result.get("grammar"), str) or not isinstance(result.get("tone"), str):
        return False
    line = normalized_key(source_text)
    for word in words:
        if not isinstance(word, dict):
            return False
        if not all(isinstance(word.get(field), str) for field in _WORD_FIELDS):
            return False
        key = normalized_key(word["text"])
        if not key or key not in line:
            return False
    return True
