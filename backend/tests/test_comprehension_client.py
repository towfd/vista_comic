"""How the Claude seam reads a response, and which model it asks.

``comprehension_client`` survived the removal ticket -- it is what the worker
calls -- but the tests that covered these two things went with the synchronous
``POST /comprehend`` endpoint they were written against. Restored here at the
seam itself, so they no longer depend on an HTTP route to say anything.

The declined signal is "no valid tool-use result", deliberately *not* a specific
``stop_reason`` value: per the spec's Further Notes it is unconfirmed whether
the cheaper Haiku tier surfaces a structured refusal the way larger models do.
Three shapes reach that conclusion by different routes and are covered
separately, because a change that broke only one of them would otherwise ship.

``comprehension_worker`` asserts what happens *to a record* on each outcome
(``test_comprehension_worker.py``); this file asserts what the client returns.
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from app import comprehension_client

_ARGS = {
    "page_image_base64": "cGFnZQ==",
    "source_text": "Xin chào",
    "target_language_code": "zh-Hant",
}


class _FakeMessages:
    def __init__(self, blocks):
        self._blocks = blocks
        self.calls: list[dict] = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        return SimpleNamespace(content=self._blocks)


class _FakeClient:
    def __init__(self, blocks):
        self.messages = _FakeMessages(blocks)


def _stub_client(monkeypatch, blocks) -> _FakeClient:
    """Replace ``_client`` so no real API key or network is used -- the same
    seam the worker's own tests substitute at."""
    fake = _FakeClient(blocks)
    monkeypatch.setattr(comprehension_client, "_client", lambda: fake)
    return fake


def _tool_use_block(**input_fields):
    return SimpleNamespace(
        type="tool_use", name=comprehension_client._TOOL_NAME, input=input_fields
    )


# --- reading the response ----------------------------------------------------


def test_a_valid_tool_use_result_is_parsed_into_all_four_fields(monkeypatch):
    _stub_client(
        monkeypatch,
        [_tool_use_block(translation="你好", grammarNotes="g", contextNotes="c", toneRegister="r")],
    )

    result = comprehension_client.comprehend(**_ARGS)

    assert result.translation == "你好"
    assert result.grammar_notes == "g"
    assert result.context_notes == "c"
    assert result.tone_register == "r"


def test_a_response_carrying_only_prose_is_declined(monkeypatch):
    _stub_client(monkeypatch, [SimpleNamespace(type="text", text="I can't help with that.")])

    assert comprehension_client.comprehend(**_ARGS) is None


def test_an_empty_response_is_declined(monkeypatch):
    _stub_client(monkeypatch, [])

    assert comprehension_client.comprehend(**_ARGS) is None


def test_a_tool_use_block_missing_fields_is_declined_rather_than_crashing(monkeypatch):
    # Should be unreachable under `strict: true`, so the point is that it
    # degrades to "declined" instead of taking the worker down with it.
    _stub_client(monkeypatch, [_tool_use_block(translation="你好")])

    assert comprehension_client.comprehend(**_ARGS) is None


def test_a_tool_use_block_for_a_different_tool_is_ignored(monkeypatch):
    _stub_client(
        monkeypatch,
        [SimpleNamespace(type="tool_use", name="something_else", input={"translation": "x"})],
    )

    assert comprehension_client.comprehend(**_ARGS) is None


# --- which model, and what is sent ------------------------------------------


def test_the_cheaper_tier_is_the_default(monkeypatch):
    fake = _stub_client(monkeypatch, [_tool_use_block(
        translation="t", grammarNotes="g", contextNotes="c", toneRegister="r"
    )])

    comprehension_client.comprehend(**_ARGS)

    # A reader who never touches the depth picker must never silently spend the
    # higher rate.
    assert fake.messages.calls[0]["model"] == comprehension_client._DEFAULT_MODEL


def test_the_stronger_tier_is_used_when_asked_for(monkeypatch):
    fake = _stub_client(monkeypatch, [_tool_use_block(
        translation="t", grammarNotes="g", contextNotes="c", toneRegister="r"
    )])

    comprehension_client.comprehend(**_ARGS, use_stronger_model=True)

    assert fake.messages.calls[0]["model"] == comprehension_client._STRONGER_MODEL


def test_only_the_page_image_is_sent(monkeypatch):
    """The selection crop left the flow with the synchronous endpoint: the call
    is deferred now, and a crop was never stored to rebuild from."""
    fake = _stub_client(monkeypatch, [_tool_use_block(
        translation="t", grammarNotes="g", contextNotes="c", toneRegister="r"
    )])

    comprehension_client.comprehend(**_ARGS)

    content = fake.messages.calls[0]["messages"][0]["content"]
    images = [block for block in content if block["type"] == "image"]
    assert len(images) == 1


def test_the_source_text_is_sent_as_text_not_left_to_the_image(monkeypatch):
    """A reader's OCR correction must not be silently overridden by the model's
    own reading of the page."""
    fake = _stub_client(monkeypatch, [_tool_use_block(
        translation="t", grammarNotes="g", contextNotes="c", toneRegister="r"
    )])

    comprehension_client.comprehend(**_ARGS)

    content = fake.messages.calls[0]["messages"][0]["content"]
    text_blocks = [block for block in content if block["type"] == "text"]
    assert any("Xin chào" in block["text"] for block in text_blocks)


def test_the_tool_call_is_forced(monkeypatch):
    fake = _stub_client(monkeypatch, [_tool_use_block(
        translation="t", grammarNotes="g", contextNotes="c", toneRegister="r"
    )])

    comprehension_client.comprehend(**_ARGS)

    assert fake.messages.calls[0]["tool_choice"] == {
        "type": "tool",
        "name": comprehension_client._TOOL_NAME,
    }
