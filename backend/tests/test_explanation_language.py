"""The tool schema tells the model which language to write the notes in.

This is the root fix for M10's second complaint: unmodified, the three
explanation fields come back in **English** -- the prompt's own language --
while ``translation`` is unaffected because its description is the only one
naming the target language. The fix is one sentence appended to each note
field's ``description``, carrying the bare BCP-47 code.

Asserted against ``_tool_schema`` directly rather than through a request. It is
a pure function of the target-language code, so this needs no API key, no stub
client and no HTTP round trip -- and it survives the endpoint that used to carry
these assertions being deleted (``comprehension-response-ux`` ticket 21). The
whole suffix is pinned rather than just the code, so the instruction cannot
silently lose its sentence.
"""

from __future__ import annotations

import pytest

from app import comprehension_client

_NOTE_FIELDS = ("grammarNotes", "contextNotes", "toneRegister")


def _properties(target_language_code: str) -> dict:
    schema = comprehension_client._tool_schema(target_language_code)
    return schema["input_schema"]["properties"]


@pytest.mark.parametrize("field", _NOTE_FIELDS)
def test_each_note_field_is_told_to_write_in_the_target_language(field):
    description = _properties("zh-Hant")[field]["description"]

    assert description.endswith("Write this field in zh-Hant.")


def test_the_translation_field_is_not_given_the_language_suffix():
    # Deliberate: `translation`'s description already names the target language
    # and was never part of the drift, so it stays exactly as the live spike
    # validated it.
    assert (
        _properties("zh-Hant")["translation"]["description"]
        == "Translation of sourceText into the target language."
    )


@pytest.mark.parametrize("code", ["ja", "vi", "zh-Hant", "en"])
def test_the_instruction_follows_whichever_target_was_asked_for(code):
    # Threaded through per request rather than hardcoded to one target -- which
    # is why the schema is built by a function instead of being a constant.
    for field in _NOTE_FIELDS:
        assert _properties(code)[field]["description"].endswith(
            f"Write this field in {code}."
        ), field


def test_every_note_field_is_still_required_of_the_model():
    schema = comprehension_client._tool_schema("zh-Hant")

    for field in _NOTE_FIELDS:
        assert field in schema["input_schema"]["required"], field
