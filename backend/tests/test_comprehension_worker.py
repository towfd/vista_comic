"""Comprehension worker tests (comprehension-response-ux ticket 16).

Every test drives ``process_pending`` directly -- the synchronous, drainable
step -- so nothing here starts a thread, sleeps, or waits. The daemon thread in
``ComprehensionWorker`` is a loop around that function and holds no decision
worth testing.

Claude is stubbed at ``comprehension_client._client``, the same seam the
``/comprehend`` tests already use, so no API key or network is ever needed.
"""

from __future__ import annotations

import base64
import io
from types import SimpleNamespace

import anthropic
import httpx
import pytest
from PIL import Image

from app import (
    comprehend_usage_store,
    comprehension_client,
    comprehension_store,
    comprehension_worker,
)


def _png_bytes(width: int, height: int) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (width, height), color=(120, 80, 200)).save(buffer, format="PNG")
    return buffer.getvalue()


@pytest.fixture
def page_file(tmp_path):
    """A real image on disk, and a resolver that finds it for any record."""
    path = tmp_path / "page.png"
    path.write_bytes(_png_bytes(900, 2500))
    return path


@pytest.fixture
def resolver(page_file):
    return lambda comic_id, chapter_id, page_number: page_file


@pytest.fixture
def session_factory(comprehension_db):
    from app import db

    return db.new_session


def _enqueue(session, **overrides) -> int:
    defaults = dict(
        source_text="À, trưởng phòng tìm cô.",
        translated_text="啊，主管在找妳。",
        target_language="zh-Hant",
        comic_id="deadbeefdeadbeef",
        chapter_id="beefdeadbeefdead",
        page_number=12,
        use_stronger_model=False,
        usage_date=comprehend_usage_store.today_utc(),
    )
    return comprehension_store.insert_record(session, **{**defaults, **overrides}).id


def _tool_use_block(**fields):
    return SimpleNamespace(
        type="tool_use", name=comprehension_client._TOOL_NAME, input=fields
    )


class _FakeMessages:
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


def _stub_claude(monkeypatch, *, blocks=None, error=None) -> _FakeClient:
    fake = _FakeClient(blocks=blocks, error=error)
    monkeypatch.setattr(comprehension_client, "_client", lambda: fake)
    return fake


def _ok_blocks():
    return [
        _tool_use_block(
            translation="啊，部門主管在找妳。",
            grammarNotes="「À」是感嘆詞…",
            contextNotes="說話者正在提醒女主角…",
            toneRegister="急迫、催促的語氣。",
        )
    ]


# --- downscaling -------------------------------------------------------------


def test_downscale_shrinks_the_long_edge_to_the_target():
    encoded = comprehension_worker.downscale_to_jpeg_base64(
        _png_bytes(900, 2500), long_edge=1024
    )

    with Image.open(io.BytesIO(base64.b64decode(encoded))) as image:
        assert max(image.size) == 1024
        # Aspect ratio preserved: 900/2500 of 1024 is 369.
        assert image.size == (369, 1024)
        assert image.format == "JPEG"


def test_downscale_never_upscales_a_small_image():
    # Blowing a small page up would cost tokens for no extra detail: Claude
    # bills roughly by pixel count.
    encoded = comprehension_worker.downscale_to_jpeg_base64(
        _png_bytes(400, 300), long_edge=1024
    )

    with Image.open(io.BytesIO(base64.b64decode(encoded))) as image:
        assert image.size == (400, 300)


def test_downscale_handles_an_image_with_an_alpha_channel():
    buffer = io.BytesIO()
    Image.new("RGBA", (2000, 1000), color=(10, 20, 30, 128)).save(buffer, format="PNG")

    encoded = comprehension_worker.downscale_to_jpeg_base64(
        buffer.getvalue(), long_edge=1024
    )

    with Image.open(io.BytesIO(base64.b64decode(encoded))) as image:
        assert image.mode == "RGB"


# --- outcomes ----------------------------------------------------------------


def test_a_successful_call_stores_the_explanation_and_marks_it_ok(
    comprehension_session, session_factory, resolver, monkeypatch
):
    _stub_claude(monkeypatch, blocks=_ok_blocks())
    record_id = _enqueue(comprehension_session)

    assert (
        comprehension_worker.process_pending(
            page_path_for=resolver, session_factory=session_factory
        )
        == 1
    )

    row = comprehension_store.get(comprehension_session, record_id)
    comprehension_session.refresh(row)
    assert row.status == comprehension_store.STATUS_OK
    assert row.cloud_translation == "啊，部門主管在找妳。"
    assert row.grammar_notes and row.context_notes and row.tone_register


def test_the_on_device_translation_is_never_modified(
    comprehension_session, session_factory, resolver, monkeypatch
):
    # Both wordings survive, so which one to show stays a UI decision.
    _stub_claude(monkeypatch, blocks=_ok_blocks())
    record_id = _enqueue(comprehension_session, translated_text="裝置端翻譯")

    comprehension_worker.process_pending(
        page_path_for=resolver, session_factory=session_factory
    )

    row = comprehension_store.get(comprehension_session, record_id)
    comprehension_session.refresh(row)
    assert row.translated_text == "裝置端翻譯"
    assert row.cloud_translation != row.translated_text


def test_a_declined_result_is_its_own_status(
    comprehension_session, session_factory, resolver, monkeypatch
):
    # No valid tool-use block is the declined signal.
    _stub_claude(monkeypatch, blocks=[SimpleNamespace(type="text", text="no")])
    record_id = _enqueue(comprehension_session)

    comprehension_worker.process_pending(
        page_path_for=resolver, session_factory=session_factory
    )

    row = comprehension_store.get(comprehension_session, record_id)
    comprehension_session.refresh(row)
    assert row.status == comprehension_store.STATUS_DECLINED


def test_any_other_api_failure_is_failed(
    comprehension_session, session_factory, resolver, monkeypatch
):
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    response = httpx.Response(500, request=request, json={"error": {}})
    _stub_claude(
        monkeypatch,
        error=anthropic.InternalServerError("boom", response=response, body=None),
    )
    record_id = _enqueue(comprehension_session)

    comprehension_worker.process_pending(
        page_path_for=resolver, session_factory=session_factory
    )

    row = comprehension_store.get(comprehension_session, record_id)
    comprehension_session.refresh(row)
    assert row.status == comprehension_store.STATUS_FAILED


def test_an_unreadable_page_fails_the_record_without_calling_claude(
    comprehension_session, session_factory, monkeypatch
):
    fake = _stub_claude(monkeypatch, blocks=_ok_blocks())
    record_id = _enqueue(comprehension_session)

    comprehension_worker.process_pending(
        page_path_for=lambda *_: None,  # comic no longer in the library
        session_factory=session_factory,
    )

    row = comprehension_store.get(comprehension_session, record_id)
    comprehension_session.refresh(row)
    assert row.status == comprehension_store.STATUS_FAILED
    assert fake.messages.calls == []


# --- the request that never reached Claude gets its reservation back ----------


def test_a_declined_result_keeps_its_reservation(
    comprehension_session, session_factory, resolver, monkeypatch
):
    # It produced billable tokens, so the budget is genuinely spent.
    _stub_claude(monkeypatch, blocks=[SimpleNamespace(type="text", text="no")])
    _enqueue(comprehension_session)
    comprehend_usage_store.check_and_increment(comprehension_session)
    spent = comprehend_usage_store.get_count(comprehension_session)

    comprehension_worker.process_pending(
        page_path_for=resolver, session_factory=session_factory
    )

    assert comprehend_usage_store.get_count(comprehension_session) == spent


def test_a_connection_failure_refunds_the_reservation(
    comprehension_session, session_factory, resolver, monkeypatch
):
    # Never reached Claude, so nothing was billed and the request is owed back.
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    _stub_claude(monkeypatch, error=anthropic.APIConnectionError(request=request))
    _enqueue(comprehension_session)
    comprehend_usage_store.check_and_increment(comprehension_session)
    spent = comprehend_usage_store.get_count(comprehension_session)

    comprehension_worker.process_pending(
        page_path_for=resolver, session_factory=session_factory
    )

    assert comprehend_usage_store.get_count(comprehension_session) == spent - 1


def test_a_timeout_keeps_its_reservation(
    comprehension_session, session_factory, resolver, monkeypatch
):
    # The trap this guards: APITimeoutError SUBCLASSES APIConnectionError, so a
    # naive `except APIConnectionError` refunds it. A timeout means the request
    # reached Claude and was billed; refunding it would understate real spend on
    # the only guard against a runaway loop.
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    _stub_claude(monkeypatch, error=anthropic.APITimeoutError(request=request))
    record_id = _enqueue(comprehension_session)
    comprehend_usage_store.check_and_increment(comprehension_session)
    spent = comprehend_usage_store.get_count(comprehension_session)

    comprehension_worker.process_pending(
        page_path_for=resolver, session_factory=session_factory
    )

    assert comprehend_usage_store.get_count(comprehension_session) == spent
    row = comprehension_store.get(comprehension_session, record_id)
    comprehension_session.refresh(row)
    assert row.status == comprehension_store.STATUS_FAILED


def test_a_missing_api_key_refunds_rather_than_draining_the_cap(
    comprehension_session, session_factory, resolver, monkeypatch
):
    # The key lookup raises before any client is constructed, so no request was
    # issued. Without an explicit branch this lands in the generic handler and a
    # misconfigured container burns one reservation per drain, silently.
    def unconfigured():
        raise RuntimeError("ANTHROPIC_API_KEY is not set.")

    monkeypatch.setattr(comprehension_client, "_client", unconfigured)
    _enqueue(comprehension_session)
    comprehend_usage_store.check_and_increment(comprehension_session)
    spent = comprehend_usage_store.get_count(comprehension_session)

    comprehension_worker.process_pending(
        page_path_for=resolver, session_factory=session_factory
    )

    assert comprehend_usage_store.get_count(comprehension_session) == spent - 1


def test_a_corrupt_page_file_fails_the_record_rather_than_stranding_it(
    comprehension_session, session_factory, tmp_path, monkeypatch
):
    # A record that escapes the drain stays `running` until the next restart,
    # holding its reservation and looking to every screen exactly like work
    # still in progress.
    fake = _stub_claude(monkeypatch, blocks=_ok_blocks())
    not_an_image = tmp_path / "broken.jpg"
    not_an_image.write_bytes(b"this is not an image")
    record_id = _enqueue(comprehension_session)

    ran = comprehension_worker.process_pending(
        page_path_for=lambda *_: not_an_image, session_factory=session_factory
    )

    assert ran == 1
    row = comprehension_store.get(comprehension_session, record_id)
    comprehension_session.refresh(row)
    assert row.status == comprehension_store.STATUS_FAILED
    assert fake.messages.calls == []


def test_an_unreadable_page_refunds_the_reservation(
    comprehension_session, session_factory
):
    _enqueue(comprehension_session)
    comprehend_usage_store.check_and_increment(comprehension_session)
    spent = comprehend_usage_store.get_count(comprehension_session)

    comprehension_worker.process_pending(
        page_path_for=lambda *_: None, session_factory=session_factory
    )

    assert comprehend_usage_store.get_count(comprehension_session) == spent - 1


# --- claiming ----------------------------------------------------------------


def test_a_drain_takes_at_most_the_limit_oldest_first(
    comprehension_session, session_factory, resolver, monkeypatch
):
    _stub_claude(monkeypatch, blocks=_ok_blocks())
    ids = [_enqueue(comprehension_session, source_text=f"line {i}") for i in range(5)]

    ran = comprehension_worker.process_pending(
        page_path_for=resolver, limit=3, session_factory=session_factory
    )

    assert ran == 3
    statuses = []
    for record_id in ids:
        row = comprehension_store.get(comprehension_session, record_id)
        comprehension_session.refresh(row)
        statuses.append(row.status)
    # The three oldest ran; the two newest are still queued.
    assert statuses[:3] == [comprehension_store.STATUS_OK] * 3
    assert statuses[3:] == [comprehension_store.STATUS_PENDING] * 2


def test_claiming_is_atomic_across_concurrent_drains(
    comprehension_session, session_factory
):
    # Two overlapping claims must never take the same row: the second skips
    # what the first has locked rather than blocking behind it.
    for i in range(4):
        _enqueue(comprehension_session, source_text=f"line {i}")

    first_session = session_factory()
    second_session = session_factory()
    try:
        first = comprehension_store.claim_pending(first_session, limit=2)
        second = comprehension_store.claim_pending(second_session, limit=2)
    finally:
        first_session.close()
        second_session.close()

    assert len(first) == 2
    assert len(second) == 2
    assert set(first).isdisjoint(second)


def test_an_empty_queue_is_a_no_op(session_factory, resolver):
    assert (
        comprehension_worker.process_pending(
            page_path_for=resolver, session_factory=session_factory
        )
        == 0
    )


def test_a_finished_record_is_not_picked_up_again(
    comprehension_session, session_factory, resolver, monkeypatch
):
    fake = _stub_claude(monkeypatch, blocks=_ok_blocks())
    _enqueue(comprehension_session)
    comprehension_worker.process_pending(
        page_path_for=resolver, session_factory=session_factory
    )

    ran = comprehension_worker.process_pending(
        page_path_for=resolver, session_factory=session_factory
    )

    assert ran == 0
    assert len(fake.messages.calls) == 1


# --- restart recovery --------------------------------------------------------


def test_orphaned_claims_are_released_back_to_pending(comprehension_session):
    # A single uvicorn worker means a just-started process cannot still be
    # running anything, so every `running` row was orphaned by a restart. This
    # is what makes `pending` genuinely mean "still being produced".
    record_id = _enqueue(comprehension_session)
    comprehension_store.claim_pending(comprehension_session, limit=1)
    row = comprehension_store.get(comprehension_session, record_id)
    comprehension_session.refresh(row)
    assert row.status == comprehension_store.STATUS_RUNNING

    released = comprehension_store.release_orphaned_claims(comprehension_session)

    comprehension_session.refresh(row)
    assert released == 1
    assert row.status == comprehension_store.STATUS_PENDING


def test_a_record_orphaned_by_a_restart_completes_on_the_next_drain(
    comprehension_session, session_factory, resolver, monkeypatch
):
    _stub_claude(monkeypatch, blocks=_ok_blocks())
    record_id = _enqueue(comprehension_session)
    comprehension_store.claim_pending(comprehension_session, limit=1)  # "crash" here

    comprehension_store.release_orphaned_claims(comprehension_session)  # restart
    comprehension_worker.process_pending(
        page_path_for=resolver, session_factory=session_factory
    )

    row = comprehension_store.get(comprehension_session, record_id)
    comprehension_session.refresh(row)
    assert row.status == comprehension_store.STATUS_OK


# --- what is actually sent ---------------------------------------------------


def test_only_the_downscaled_page_is_sent_and_the_tier_comes_from_the_row(
    comprehension_session, session_factory, resolver, monkeypatch
):
    fake = _stub_claude(monkeypatch, blocks=_ok_blocks())
    _enqueue(comprehension_session, use_stronger_model=True)

    comprehension_worker.process_pending(
        page_path_for=resolver, session_factory=session_factory
    )

    sent = fake.messages.calls[0]
    assert sent["model"] == comprehension_client._STRONGER_MODEL
    content = sent["messages"][0]["content"]
    images = [block for block in content if block["type"] == "image"]
    # Page only: the selection crop is gone from the flow, because a call
    # deferred by minutes cannot reconstruct one.
    assert len(images) == 1
    with Image.open(
        io.BytesIO(base64.b64decode(images[0]["source"]["data"]))
    ) as image:
        assert max(image.size) == comprehension_worker.PAGE_IMAGE_LONG_EDGE


def test_the_claude_client_is_built_with_a_bounded_per_attempt_timeout(monkeypatch):
    # The SDK default is 600s, which a worker with three concurrency slots
    # cannot afford: one hung call would hold a slot for ten minutes. Asserts
    # the constructed client actually carries it, not just that a constant says
    # so -- the constant existing proves nothing about it being applied.
    monkeypatch.setattr(
        comprehension_client, "get_claude_api_key", lambda: "sk-test-not-a-real-key"
    )

    client = comprehension_client._client()

    assert client.timeout == 120.0
