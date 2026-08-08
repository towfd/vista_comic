"""The request must ask for a word-level breakdown, not just an explanation.

M11's complaint from real use: explanations came back describing the sentence
while never saying what the individual words meant -- which is the one thing a
learner reading a foreign comic most needs. Nothing in the old schema or prompt
asked for vocabulary, so a model that skipped it was answering correctly.

The instruction is deliberately carried on the existing ``grammarNotes`` field
rather than a new ``vocabularyNotes`` one: a new field means a DB column, a
migration, an API model change and an app change, and the outcome the reader
asked for is reachable without any of that.

Asserted against ``_tool_schema``/``_prompt_text`` directly, mirroring
``test_explanation_language.py``'s reasoning: both are pure functions, so this
needs no API key, no stub client and no HTTP round trip.
"""

from __future__ import annotations

from app import comprehension_client


def _grammar_description(target_language_code: str = "zh-Hant") -> str:
    schema = comprehension_client._tool_schema(target_language_code)
    return schema["input_schema"]["properties"]["grammarNotes"]["description"]


def test_the_grammar_field_demands_a_vocabulary_breakdown():
    description = _grammar_description()

    assert "vocabulary breakdown" in description
    # The shape matters as much as the demand: a paragraph mentioning a few
    # words is what this replaces, so the per-word, per-line format is pinned.
    assert "one by one" in description
    assert "its own line" in description


def test_the_grammar_field_still_asks_for_grammar_too():
    # Vocabulary is added to this field, not swapped in for what it carried.
    description = _grammar_description()

    assert "grammar and structure" in description


def test_the_grammar_field_keeps_its_target_language_instruction():
    # The vocabulary sentences must not push the language instruction off the
    # end of the description -- `note()` appends it last, and
    # `test_explanation_language.py` pins that it stays there.
    assert _grammar_description("ja").endswith("Write this field in ja.")


def test_the_prompt_also_asks_for_the_breakdown():
    # Stated in both places on purpose: the schema description is what the
    # model reads per field, and the prompt is what sets the overall bar for
    # thoroughness. A model that skims one still sees the other.
    prompt = comprehension_client._prompt_text("Xin chào", "zh-Hant")

    assert "word-by-word vocabulary" in prompt
    assert "incomplete" in prompt


def test_the_output_ceiling_leaves_room_for_a_word_list():
    # A truncated word list is exactly the missing-vocabulary complaint this
    # change exists to fix, so the ceiling was raised alongside the prompt.
    assert comprehension_client._MAX_OUTPUT_TOKENS >= 2048
