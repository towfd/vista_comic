"""Client wrapper around the Claude Messages API backing ``POST /comprehend``.

Mirrors ``progress_store.py``/``translation_store.py``'s "thin functions over a
fresh resource" shape: instead of a SQLAlchemy ``Session``, the resource here
is an ``anthropic.Anthropic`` client, constructed fresh per call from
``config.get_claude_api_key()`` (never hardcoded, never logged). ``_client()``
is a small seam so tests substitute a stub client without a real API key,
mirroring how ``db.new_session()`` is monkeypatched in the store tests.

Sends both the selection crop (original resolution) and the downscaled full
page as image content blocks, plus ``source_text`` as plain text -- Claude
translates/explains *that* text; it is never asked to re-read text from the
images (a user's OCR correction must not be silently overridden by the
model's own reading of the crop).

Uses a ``strict: true`` tool-use schema (``additionalProperties: false``, all
four fields ``required``) and forces the tool call via ``tool_choice``, so a
successful response's ``input`` is guaranteed to have exactly these fields.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Optional

import anthropic

from .config import get_claude_api_key

# Per the installed `anthropic` SDK's own model literals
# (`anthropic.types.model_param.ModelParam`), confirmed via
# `pip show anthropic` (0.120.2) in backend/.venv. Default: Claude Haiku 4.5
# (dated ID, matching the SDK's own literal). Stronger tier: Claude Sonnet 5,
# selected when the request's `useStrongerModel` is true (ticket 17 wires up
# the UI trigger; the parameter exists starting this ticket).
_DEFAULT_MODEL = "claude-haiku-4-5-20251001"
_STRONGER_MODEL = "claude-sonnet-5"

_MAX_OUTPUT_TOKENS = 1024

_TOOL_NAME = "record_comprehension"

# strict: true + additionalProperties: false + all four fields required,
# per the spec's Implementation Decisions and ticket 06's validated schema.
_TOOL_SCHEMA: dict[str, Any] = {
    "name": _TOOL_NAME,
    "description": (
        "Record the translation and explanation of the given source text, "
        "using the two images only for visual context (speaker, panel, "
        "tone) -- never as the source of the text itself."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "translation": {
                "type": "string",
                "description": "Translation of sourceText into the target language.",
            },
            "grammarNotes": {
                "type": "string",
                "description": "Notes on the sentence's grammar/structure.",
            },
            "contextNotes": {
                "type": "string",
                "description": (
                    "How the surrounding panel/page (visible in the images) "
                    "resolves ambiguity in the text (e.g. pronouns)."
                ),
            },
            "toneRegister": {
                "type": "string",
                "description": "The line's tone/register/formality.",
            },
        },
        "required": ["translation", "grammarNotes", "contextNotes", "toneRegister"],
        "additionalProperties": False,
    },
    "strict": True,
}


@dataclass(frozen=True)
class ComprehensionResult:
    """The four structured fields Claude returns on a successful tool call."""

    translation: str
    grammar_notes: str
    context_notes: str
    tone_register: str


def _client() -> anthropic.Anthropic:
    """Construct a fresh Anthropic client from the configured API key.

    A thin seam so tests substitute a stub client (mirrors ``db.new_session``'s
    role for the DB-backed stores) -- monkeypatch this function rather than
    calling the real Anthropic API in the test suite.
    """
    return anthropic.Anthropic(api_key=get_claude_api_key())


def _image_block(base64_data: str) -> dict[str, Any]:
    # The request contract (ComprehendRequest) does not carry a media-type
    # field alongside each base64 image; both the crop and the downscaled
    # page image are assumed JPEG, matching this backend's own re-encoded
    # network payloads elsewhere. Revisit if a non-JPEG source turns out to
    # reach this endpoint in practice.
    return {
        "type": "image",
        "source": {
            "type": "base64",
            "media_type": "image/jpeg",
            "data": base64_data,
        },
    }


def _prompt_text(source_text: str, target_language_code: str) -> str:
    return (
        "The source text below is the ground truth for the selected speech "
        "bubble -- it may be a user's correction of the OCR reading, so "
        "translate and explain exactly this text; do not re-read or "
        "re-derive the text from the images. Use the two images (the "
        "selection crop, then the full page) only for visual context "
        "(who is speaking, what is happening in the panel, tone) to inform "
        "grammarNotes/contextNotes/toneRegister and to resolve ambiguity "
        "(e.g. pronouns) in the translation.\n\n"
        f"Source text: {source_text}\n"
        f"Target language code: {target_language_code}"
    )


def comprehend(
    *,
    crop_image_base64: str,
    page_image_base64: str,
    source_text: str,
    target_language_code: str,
    use_stronger_model: bool = False,
) -> Optional[ComprehensionResult]:
    """Call Claude for a structured translation + explanation.

    Returns the parsed result on a successful tool-use response, or ``None``
    when the response contains no valid tool-use block matching the forced
    tool -- this is the "declined" signal. Deliberately does NOT gate on a
    specific ``stop_reason``/``stop_details`` value being present: per the
    spec's Further Notes, it is unconfirmed whether the cheaper Haiku tier
    surfaces a structured refusal (``stop_reason: "refusal"``) the same way
    larger models do, so "no valid tool-use result" alone is the signal used.

    Any other failure (a connection/API error from the SDK, or a malformed
    tool-use ``input`` that should be impossible under ``strict: true``)
    propagates as an exception; the caller (``main.comprehend_endpoint``) maps
    that to an HTTP 4xx/5xx rather than a 200.
    """
    model = _STRONGER_MODEL if use_stronger_model else _DEFAULT_MODEL
    client = _client()
    message = client.messages.create(
        model=model,
        max_tokens=_MAX_OUTPUT_TOKENS,
        tools=[_TOOL_SCHEMA],
        tool_choice={"type": "tool", "name": _TOOL_NAME},
        messages=[
            {
                "role": "user",
                "content": [
                    _image_block(crop_image_base64),
                    _image_block(page_image_base64),
                    {
                        "type": "text",
                        "text": _prompt_text(source_text, target_language_code),
                    },
                ],
            }
        ],
    )

    for block in message.content:
        if getattr(block, "type", None) == "tool_use" and block.name == _TOOL_NAME:
            data = block.input
            try:
                return ComprehensionResult(
                    translation=data["translation"],
                    grammar_notes=data["grammarNotes"],
                    context_notes=data["contextNotes"],
                    tone_register=data["toneRegister"],
                )
            except (KeyError, TypeError):
                # Should be unreachable under strict: true; treated as a
                # declined/invalid result rather than crashing the request.
                return None
    return None
