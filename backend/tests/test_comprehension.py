"""Backend tests for ``POST /comprehend`` (llm-comprehension ticket 11).

Mocks/stubs the Anthropic client at ``comprehension_client._client``'s seam
(mirrors how the DB-backed stores are stubbed via ``db.new_session`` /
``db._SessionLocal`` in ``test_translation.py``/``test_progress.py``), so the
suite never makes a real call to Anthropic's API and never needs a real API
key. No catalog or DB fixture is needed: ``/comprehend`` talks only to Claude,
not the scanner or Postgres, so ``TestClient(main.app)`` is built directly
(not as a context manager, so the startup lifespan never runs) — same
rationale as ``test_translation.py``'s ``client`` fixture.
"""

from __future__ import annotations

from types import SimpleNamespace

import anthropic
import httpx
import pytest
from fastapi.testclient import TestClient

from app import comprehension_client, main

_BODY = {
    "cropImageBase64": "Y3JvcA==",
    "pageImageBase64": "cGFnZQ==",
    "sourceText": "Xin chào",
    "targetLanguageCode": "zh-Hant",
}


@pytest.fixture
def client():
    return TestClient(main.app)


def _tool_use_block(**input_fields):
    return SimpleNamespace(
        type="tool_use",
        name=comprehension_client._TOOL_NAME,
        input=input_fields,
    )


def _text_block(text: str = "I can't help with that."):
    return SimpleNamespace(type="text", text=text)


class _FakeMessages:
    """Stand-in for ``anthropic.Anthropic().messages``."""

    def __init__(self, *, blocks=None, error=None):
        self._blocks = blocks
        self._error = error
        self.calls: list[dict] = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if self._error is not None:
            raise self._error
        return SimpleNamespace(content=self._blocks)


class _FakeClient:
    def __init__(self, *, blocks=None, error=None):
        self.messages = _FakeMessages(blocks=blocks, error=error)


def _stub_client(monkeypatch, *, blocks=None, error=None) -> _FakeClient:
    """Replace ``comprehension_client._client`` so no real API key/network is used."""
    fake = _FakeClient(blocks=blocks, error=error)
    monkeypatch.setattr(comprehension_client, "_client", lambda: fake)
    return fake


# --- success: status "ok" with all four fields -------------------------------


def test_comprehend_success_returns_ok_with_all_four_fields(client, monkeypatch):
    block = _tool_use_block(
        translation="你好",
        grammarNotes="Subject-verb-object order.",
        contextNotes="The page shows two people greeting each other.",
        toneRegister="Casual, friendly.",
    )
    fake = _stub_client(monkeypatch, blocks=[block])

    resp = client.post("/comprehend", json=_BODY)

    assert resp.status_code == 200
    assert resp.json() == {
        "status": "ok",
        "translation": "你好",
        "grammarNotes": "Subject-verb-object order.",
        "contextNotes": "The page shows two people greeting each other.",
        "toneRegister": "Casual, friendly.",
    }
    # Exactly one call, forcing the tool via tool_choice, defaulting to Haiku.
    assert len(fake.messages.calls) == 1
    sent = fake.messages.calls[0]
    assert sent["model"] == comprehension_client._DEFAULT_MODEL
    assert sent["tool_choice"] == {
        "type": "tool",
        "name": comprehension_client._TOOL_NAME,
    }
    assert sent["tools"][0]["strict"] is True
    assert sent["tools"][0]["input_schema"]["additionalProperties"] is False
    assert set(sent["tools"][0]["input_schema"]["required"]) == {
        "translation",
        "grammarNotes",
        "contextNotes",
        "toneRegister",
    }


def test_comprehend_uses_stronger_model_when_requested(client, monkeypatch):
    block = _tool_use_block(
        translation="t", grammarNotes="g", contextNotes="c", toneRegister="r"
    )
    fake = _stub_client(monkeypatch, blocks=[block])

    resp = client.post("/comprehend", json={**_BODY, "useStrongerModel": True})

    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
    assert fake.messages.calls[0]["model"] == comprehension_client._STRONGER_MODEL


def test_comprehend_defaults_to_haiku_when_tier_field_omitted(client, monkeypatch):
    block = _tool_use_block(
        translation="t", grammarNotes="g", contextNotes="c", toneRegister="r"
    )
    fake = _stub_client(monkeypatch, blocks=[block])

    resp = client.post("/comprehend", json=_BODY)

    assert resp.status_code == 200
    assert fake.messages.calls[0]["model"] == comprehension_client._DEFAULT_MODEL


# --- declined: no valid tool-use block, regardless of stop_reason -----------


def test_comprehend_declined_when_response_has_only_a_text_block(client, monkeypatch):
    _stub_client(monkeypatch, blocks=[_text_block()])

    resp = client.post("/comprehend", json=_BODY)

    assert resp.status_code == 200
    assert resp.json() == {"status": "declined"}


def test_comprehend_declined_when_content_is_empty(client, monkeypatch):
    _stub_client(monkeypatch, blocks=[])

    resp = client.post("/comprehend", json=_BODY)

    assert resp.status_code == 200
    assert resp.json() == {"status": "declined"}


def test_comprehend_declined_when_tool_use_input_is_malformed(client, monkeypatch):
    # Defensive case: a tool_use block naming the right tool but missing a
    # required key (should be unreachable under strict: true) still resolves
    # to "declined" rather than a 500.
    block = SimpleNamespace(
        type="tool_use",
        name=comprehension_client._TOOL_NAME,
        input={"translation": "t"},  # missing the other three fields
    )
    _stub_client(monkeypatch, blocks=[block])

    resp = client.post("/comprehend", json=_BODY)

    assert resp.status_code == 200
    assert resp.json() == {"status": "declined"}


# --- other failures: 4xx/5xx, never a 200 ------------------------------------


def test_comprehend_connection_error_surfaces_as_502(client, monkeypatch):
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    _stub_client(monkeypatch, error=anthropic.APIConnectionError(request=request))

    resp = client.post("/comprehend", json=_BODY)

    assert resp.status_code == 502
    assert resp.json()["detail"]


def test_comprehend_api_status_error_forwards_claudes_status_code(client, monkeypatch):
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    response = httpx.Response(
        429,
        request=request,
        json={"error": {"type": "rate_limit_error", "message": "rate limited"}},
    )
    error = anthropic.RateLimitError(
        "rate limited", response=response, body=response.json()
    )
    _stub_client(monkeypatch, error=error)

    resp = client.post("/comprehend", json=_BODY)

    assert resp.status_code == 429
    assert resp.json()["detail"]


def test_comprehend_generic_anthropic_error_surfaces_as_502(client, monkeypatch):
    _stub_client(monkeypatch, error=anthropic.AnthropicError("unexpected SDK error"))

    resp = client.post("/comprehend", json=_BODY)

    assert resp.status_code == 502


# --- malformed request: 422 before any Claude call --------------------------


@pytest.mark.parametrize(
    "missing_field",
    ["cropImageBase64", "pageImageBase64", "sourceText", "targetLanguageCode"],
)
def test_comprehend_missing_required_field_422(client, missing_field):
    body = {k: v for k, v in _BODY.items() if k != missing_field}
    resp = client.post("/comprehend", json=body)
    assert resp.status_code == 422


def test_comprehend_missing_field_never_reaches_claude(client, monkeypatch):
    fake = _stub_client(monkeypatch, blocks=[])
    body = {k: v for k, v in _BODY.items() if k != "sourceText"}

    resp = client.post("/comprehend", json=body)

    assert resp.status_code == 422
    assert fake.messages.calls == []


# --- explanation language (comprehension-response-ux ticket 14) ---------------


_NOTE_FIELDS = ("grammarNotes", "contextNotes", "toneRegister")


def _schema_properties(fake) -> dict:
    return fake.messages.calls[0]["tools"][0]["input_schema"]["properties"]


def _ok_block():
    return _tool_use_block(
        translation="t", grammarNotes="g", contextNotes="c", toneRegister="r"
    )


def test_note_fields_are_told_to_write_in_the_target_language(client, monkeypatch):
    fake = _stub_client(monkeypatch, blocks=[_ok_block()])

    resp = client.post("/comprehend", json=_BODY)

    assert resp.status_code == 200
    # Asserted on the schema sent to the model, not on generated prose, so this
    # stays deterministic and needs no API key. The full suffix is pinned, not
    # just the code, so the instruction can't silently lose its sentence.
    properties = _schema_properties(fake)
    for field in _NOTE_FIELDS:
        assert properties[field]["description"].endswith(
            "Write this field in zh-Hant."
        ), field


def test_translation_field_is_not_given_the_language_suffix(client, monkeypatch):
    fake = _stub_client(monkeypatch, blocks=[_ok_block()])

    resp = client.post("/comprehend", json=_BODY)

    assert resp.status_code == 200
    # Deliberate: `translation` already names the target language and was never
    # part of the drift, so it must stay exactly as ticket 06 validated it.
    assert (
        _schema_properties(fake)["translation"]["description"]
        == "Translation of sourceText into the target language."
    )


def test_note_language_follows_the_requested_target(client, monkeypatch):
    fake = _stub_client(monkeypatch, blocks=[_ok_block()])

    resp = client.post("/comprehend", json={**_BODY, "targetLanguageCode": "ja"})

    assert resp.status_code == 200
    # Threaded through per request, not hardcoded to one target.
    properties = _schema_properties(fake)
    for field in _NOTE_FIELDS:
        assert properties[field]["description"].endswith("Write this field in ja."), field
