"""The request the line-analysis client builds, and how it reads the answer.

No call ever leaves the process: ``line_analysis_client._client`` is replaced
by a stub whose ``beta.messages.stream`` records the request and plays back a
canned final message.
"""

from __future__ import annotations

import json
from types import SimpleNamespace

import pytest

from app import line_analysis_client as client
from app.line_analysis_client import InvalidAnalysis, Name

_LINE = "Anh Dok-ja, viện phí đã thanh toán rồi à?"
_TRANSLATION = "獨子哥，住院費已經付了嗎？"

_GOOD = {
    "words": [
        {"text": "Anh", "meaning": "哥", "partOfSpeech": "代名詞", "hanViet": "英", "note": ""},
        {"text": "Dok-ja", "meaning": "獨子", "partOfSpeech": "人名", "hanViet": "", "note": ""},
        {"text": "viện phí", "meaning": "住院費", "partOfSpeech": "名詞", "hanViet": "院費", "note": ""},
        {"text": "đã", "meaning": "已經", "partOfSpeech": "副詞", "hanViet": "", "note": ""},
        {"text": "thanh toán", "meaning": "付", "partOfSpeech": "動詞", "hanViet": "清算", "note": ""},
        {"text": "rồi à", "meaning": "了嗎", "partOfSpeech": "語氣詞", "hanViet": "", "note": "確認語氣"},
    ],
    "grammar": "…",
    "tone": "…",
}


def _text(value: str):
    return SimpleNamespace(type="text", text=value)


class _Stream:
    def __init__(self, message):
        self._message = message

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def get_final_message(self):
        return self._message


@pytest.fixture
def stub(monkeypatch):
    """Answer every call with ``stub.message``; record each request in ``stub.requests``."""
    state = SimpleNamespace(
        requests=[],
        message=SimpleNamespace(stop_reason="end_turn", content=[_text(json.dumps(_GOOD))]),
    )

    def stream(**request):
        state.requests.append(request)
        return _Stream(state.message)

    fake = SimpleNamespace(beta=SimpleNamespace(messages=SimpleNamespace(stream=stream)))
    monkeypatch.setattr(client, "_client", lambda: fake)
    return state


def _analyse(model="sonnet", names=()):
    return client.analyse(
        model=model, source_text=_LINE, translation=_TRANSLATION, names=list(names)
    )


# --- the request -------------------------------------------------------------


@pytest.mark.parametrize(
    "model, model_id",
    [("sonnet", "claude-sonnet-5-5"), ("opus", "claude-opus-5-5"), ("fable", "claude-fable-5-1")],
)
def test_the_readers_choice_is_mapped_to_a_model_id(stub, model, model_id):
    _analyse(model)

    assert stub.requests[0]["model"] == model_id


def test_the_answer_is_pinned_by_a_json_schema_not_a_forced_tool(stub):
    _analyse()
    request = stub.requests[0]

    assert request["output_config"] == {
        "format": {"type": "json_schema", "schema": client.SCHEMA}
    }
    assert "tools" not in request and "tool_choice" not in request
    word = client.SCHEMA["properties"]["words"]["items"]
    assert word["required"] == ["text", "meaning", "partOfSpeech", "hanViet", "note"]
    assert word["additionalProperties"] is False
    assert word["properties"]["partOfSpeech"]["enum"][:3] == ["名詞", "動詞", "形容詞"]
    assert len(word["properties"]["partOfSpeech"]["enum"]) == 16


def test_the_agreed_prompt_goes_in_as_the_system_prompt(stub):
    _analyse()
    system = stub.requests[0]["system"]

    assert system == client.SYSTEM_PROMPT
    assert "The translation is final" in system
    assert "Split the line into words, not syllables" in system


def test_the_user_turn_carries_the_names_the_line_and_the_translation_and_no_image(stub):
    _analyse(names=[Name(source="Dok-ja", target="獨子")])
    [message] = stub.requests[0]["messages"]

    assert message["role"] == "user"
    assert isinstance(message["content"], str)  # text only: no image block
    assert "Dok-ja = 獨子" in message["content"]
    assert _LINE in message["content"]
    assert _TRANSLATION in message["content"]


def test_an_empty_name_table_says_so(stub):
    _analyse()

    assert "<names>\n(none)\n</names>" in stub.requests[0]["messages"][0]["content"]


def test_thinking_is_adaptive_and_refusals_fall_back_server_side(stub):
    _analyse()
    request = stub.requests[0]

    assert request["thinking"] == {"type": "adaptive"}
    assert request["fallbacks"] == "default"
    assert request["betas"] == ["server-side-fallback-2026-07-01"]


# --- reading the answer --------------------------------------------------------


def test_a_good_answer_is_parsed(stub):
    assert _analyse() == _GOOD


def test_a_refusal_is_reported_as_refused(stub):
    stub.message = SimpleNamespace(stop_reason="refusal", content=[])

    assert _analyse() is client.REFUSED


def test_an_answer_cut_off_at_max_tokens_is_invalid(stub):
    stub.message = SimpleNamespace(stop_reason="max_tokens", content=[_text('{"words": [')])

    with pytest.raises(InvalidAnalysis):
        _analyse()


def test_an_answer_that_is_not_json_is_invalid(stub):
    stub.message = SimpleNamespace(stop_reason="end_turn", content=[_text("Sorry, no.")])

    with pytest.raises(InvalidAnalysis):
        _analyse()


def test_only_the_text_after_a_fallback_switch_is_the_answer(stub):
    stub.message = SimpleNamespace(
        stop_reason="end_turn",
        content=[
            _text('{"words": [{"te'),
            SimpleNamespace(type="fallback"),
            _text(json.dumps(_GOOD)),
        ],
    )

    assert _analyse() == _GOOD


# --- is the answer usable -------------------------------------------------------


def test_a_complete_answer_is_usable():
    assert client.is_usable(_GOOD, _LINE)


def test_words_match_the_line_ignoring_case_and_spacing():
    upper = {**_GOOD, "words": [{**_GOOD["words"][2], "text": "VIỆN  PHÍ"}]}

    assert client.is_usable(upper, _LINE.upper())


def test_an_answer_with_no_words_is_not_usable():
    assert not client.is_usable({**_GOOD, "words": []}, _LINE)


def test_a_word_not_in_the_line_is_not_usable():
    stray = {**_GOOD, "words": [*_GOOD["words"], {**_GOOD["words"][0], "text": "bệnh viện"}]}

    assert not client.is_usable(stray, _LINE)


@pytest.mark.parametrize(
    "broken",
    [
        None,
        [],
        {"words": [{"text": "Anh"}], "grammar": "", "tone": ""},
        {"words": _GOOD["words"], "grammar": None, "tone": ""},
        {"words": [{**_GOOD["words"][0], "text": "   "}], "grammar": "", "tone": ""},
    ],
)
def test_a_malformed_answer_is_not_usable(broken):
    assert not client.is_usable(broken, _LINE)
