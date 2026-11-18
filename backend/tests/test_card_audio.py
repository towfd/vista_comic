"""Card audio: written by the Text-To-Speech repo, served here (card-audio ticket 01).

Runs against the throwaway Postgres database (see ``conftest.py``), with
``learning_card`` and ``card_audio`` truncated before each test.

The real writer lives in another repo and connects as its own role, so these
tests stand in for it by writing ``card_audio`` rows directly: the table is the
whole contract between the two repos. See ``.scratch/card-audio/spec.md``.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, inspect, select

from app import main
from app.db import CardAudio, LearningCard

_BODY = {
    "sourceText": "không biết",
    "translation": "不知道",
    "targetLanguage": "zh-Hant",
    "comicId": "deadbeefdeadbeef",
    "chapterId": "beefdeadbeefdead",
    "pageNumber": 3,
}

_MP3 = b"ID3-not-really-an-mp3"
_MADE_AT = datetime(2026, 11, 18, 9, 0, tzinfo=timezone.utc)


@pytest.fixture
def client(learning_card_db):
    return TestClient(main.app)


def _add(client, **overrides):
    return client.post("/cards", json={**_BODY, **overrides})


def _fix(client, card_id, text):
    return client.put(f"/cards/{card_id}/source-text", json={"sourceText": text})


def _record(
    session,
    card_id: int,
    source_text: str,
    *,
    audio: bytes = _MP3,
    mime_type: str = "audio/mpeg",
    created_at: datetime = _MADE_AT,
) -> None:
    """Write a card's recording as the writer does: insert it, or overwrite it."""
    session.merge(
        CardAudio(
            card_id=card_id,
            source_text=source_text,
            voice="vi-VN-Chirp3-HD-Achernar",
            mime_type=mime_type,
            audio=audio,
            created_at=created_at,
        )
    )
    session.commit()


@pytest.fixture
def recorded(client, learning_card_session):
    """One card with a recording of its current text; returns the card."""
    card = _add(client).json()
    _record(learning_card_session, card["id"], card["sourceText"])
    return card


def _audio_url(card) -> str:
    return f"/cards/{card['id']}/audio"


# --- serving the recording ---------------------------------------------------


def test_a_current_recording_is_served_with_its_type_and_validators(
    client, recorded
):
    resp = client.get(_audio_url(recorded))

    assert resp.status_code == 200, resp.text
    assert resp.content == _MP3
    assert resp.headers["content-type"] == "audio/mpeg"
    # The URL stays the same when the writer remakes the recording, so the
    # client has to ask every time; the ETag makes asking cheap.
    assert resp.headers["cache-control"] == "no-cache"
    etag = resp.headers["etag"]
    assert etag.startswith('"') and etag.endswith('"') and len(etag) > 2


def test_the_content_type_is_the_rows_own(client, learning_card_session):
    """Served from ``mime_type`` rather than assumed to be MP3."""
    card = _add(client).json()
    _record(learning_card_session, card["id"], card["sourceText"], mime_type="audio/ogg")

    assert client.get(_audio_url(card)).headers["content-type"] == "audio/ogg"


@pytest.mark.parametrize(
    "header",
    ["{etag}", "W/{etag}", '"something-else", {etag}', "*"],
    ids=["exact", "weak", "in a list", "any"],
)
def test_a_current_copy_is_answered_304_without_the_bytes(client, recorded, header):
    """nginx or Cloudflare may hand the tag back weak (``W/``) or in a list."""
    etag = client.get(_audio_url(recorded)).headers["etag"]

    resp = client.get(
        _audio_url(recorded), headers={"If-None-Match": header.format(etag=etag)}
    )

    assert resp.status_code == 304
    assert resp.content == b""
    # A 304 repeats the validators, so the client keeps checking next time.
    assert resp.headers["etag"] == etag
    assert resp.headers["cache-control"] == "no-cache"


def test_another_etag_gets_the_recording(client, recorded):
    resp = client.get(_audio_url(recorded), headers={"If-None-Match": '"something-else"'})

    assert resp.status_code == 200
    assert resp.content == _MP3


def test_the_etag_holds_until_the_recording_is_remade(
    client, learning_card_session, recorded
):
    """The writer overwrites the row; its ``created_at`` is what moves."""
    first = client.get(_audio_url(recorded)).headers["etag"]
    assert client.get(_audio_url(recorded)).headers["etag"] == first

    _record(
        learning_card_session,
        recorded["id"],
        recorded["sourceText"],
        audio=b"ID3-remade",
        created_at=_MADE_AT + timedelta(minutes=1),
    )
    resp = client.get(_audio_url(recorded), headers={"If-None-Match": first})

    assert resp.status_code == 200
    assert resp.content == b"ID3-remade"
    assert resp.headers["etag"] != first


def test_two_cards_made_at_the_same_moment_have_different_etags(
    client, learning_card_session
):
    """One run of the writer stamps many rows; the card id keeps them apart."""
    one = _add(client, sourceText="cảm ơn").json()
    two = _add(client, sourceText="xin chào").json()
    _record(learning_card_session, one["id"], "cảm ơn")
    _record(learning_card_session, two["id"], "xin chào")

    assert (
        client.get(_audio_url(one)).headers["etag"]
        != client.get(_audio_url(two)).headers["etag"]
    )


# --- what has no recording ---------------------------------------------------


def test_a_card_that_does_not_exist_has_no_audio(client):
    assert client.get("/cards/999999/audio").status_code == 404


def test_a_card_without_a_recording_has_no_audio(client):
    card = _add(client).json()

    assert client.get(_audio_url(card)).status_code == 404


def test_a_recording_of_an_older_text_is_not_served(client, learning_card_session):
    """A correction leaves the row in place, and the row says the old words."""
    card = _add(client, sourceText="khong biet").json()
    _record(learning_card_session, card["id"], "khong biet")
    etag = client.get(_audio_url(card)).headers["etag"]

    _fix(client, card["id"], "không biết")

    assert client.get(_audio_url(card)).status_code == 404
    # Not even as "your copy is still good": the copy is of the old text.
    assert (
        client.get(_audio_url(card), headers={"If-None-Match": etag}).status_code
        == 404
    )


def test_an_unavailable_store_is_not_reported_as_no_audio(client, monkeypatch):
    """A 404 tells the client the card has nothing to play; an outage is not that."""

    def unavailable():
        raise RuntimeError("Database engine not initialized")

    monkeypatch.setattr(main, "new_session", unavailable)

    assert client.get("/cards/1/audio").status_code == 503


# --- hasAudio on every card response -----------------------------------------


def test_the_deck_says_which_cards_have_a_current_recording(
    client, learning_card_session
):
    current = _add(client, sourceText="cảm ơn").json()
    without = _add(client, sourceText="xin chào").json()
    stale = _add(client, sourceText="khong biet").json()
    _record(learning_card_session, current["id"], "cảm ơn")
    _record(learning_card_session, stale["id"], "không biết")

    listed = {card["id"]: card["hasAudio"] for card in client.get("/cards").json()}

    assert listed == {current["id"]: True, without["id"]: False, stale["id"]: False}


def test_a_new_card_has_no_audio(client):
    assert _add(client).json()["hasAudio"] is False


def test_a_correction_answers_that_the_recording_no_longer_applies(
    client, learning_card_session
):
    card = _add(client, sourceText="khong biet").json()
    _record(learning_card_session, card["id"], "khong biet")

    resp = _fix(client, card["id"], "không biết")

    assert resp.status_code == 200, resp.text
    assert resp.json()["hasAudio"] is False
    assert client.get("/cards").json()[0]["hasAudio"] is False


def test_correcting_back_to_the_recorded_text_makes_it_current_again(
    client, learning_card_session
):
    """Compared on read, not deleted: the row was never touched."""
    card = _add(client, sourceText="khong biet").json()
    _record(learning_card_session, card["id"], "khong biet")
    _fix(client, card["id"], "không biết")

    resp = _fix(client, card["id"], "khong biet")

    assert resp.json()["hasAudio"] is True
    assert client.get(_audio_url(card)).status_code == 200


def test_the_same_text_again_keeps_the_recording(client, recorded):
    resp = _fix(client, recorded["id"], recorded["sourceText"])

    assert resp.status_code == 200
    assert resp.json()["hasAudio"] is True


def test_a_refused_correction_names_the_other_card_with_its_audio(
    client, learning_card_session
):
    typo = _add(client, sourceText="khong biet").json()
    other = _add(client, sourceText="không biết").json()
    _record(learning_card_session, other["id"], "không biết")

    resp = _fix(client, typo["id"], "Không biết")

    assert resp.status_code == 409
    assert resp.json()["card"]["id"] == other["id"]
    assert resp.json()["card"]["hasAudio"] is True


@pytest.mark.parametrize("has_recording", [True, False], ids=["recorded", "silent"])
def test_collecting_a_card_again_answers_with_its_audio(
    client, learning_card_session, has_recording
):
    card = _add(client).json()
    if has_recording:
        _record(learning_card_session, card["id"], card["sourceText"])

    again = _add(client)

    assert again.status_code == 200
    assert again.json()["hasAudio"] is has_recording


def test_a_revived_card_answers_with_its_audio(client, learning_card_session, recorded):
    """Collecting an archived line revives it, writing the row on the way."""
    row = learning_card_session.get(LearningCard, recorded["id"])
    row.archived_at = datetime.now(timezone.utc)
    learning_card_session.commit()

    again = _add(client)

    assert again.status_code == 200
    assert again.json()["id"] == recorded["id"]
    assert again.json()["hasAudio"] is True


@pytest.mark.parametrize("has_recording", [True, False], ids=["recorded", "silent"])
def test_an_edit_answers_with_the_cards_audio(
    client, learning_card_session, has_recording
):
    card = _add(client).json()
    if has_recording:
        _record(learning_card_session, card["id"], card["sourceText"])

    resp = client.patch(f"/cards/{card['id']}", json={"translation": "không rõ"})

    assert resp.status_code == 200, resp.text
    assert resp.json()["hasAudio"] is has_recording


@pytest.mark.parametrize("has_recording", [True, False], ids=["recorded", "silent"])
def test_a_reset_answers_with_the_cards_audio(
    client, learning_card_session, has_recording
):
    """The reset writes the card, which makes SQLAlchemy reload the flag."""
    card = _add(client).json()
    if has_recording:
        _record(learning_card_session, card["id"], card["sourceText"])

    resp = client.post(f"/cards/{card['id']}/reset")

    assert resp.status_code == 200, resp.text
    assert resp.json()["hasAudio"] is has_recording


# --- the row belongs to its card ---------------------------------------------


def test_deleting_a_card_deletes_its_recording(client, learning_card_session, recorded):
    assert client.delete(f"/cards/{recorded['id']}").status_code == 204

    left = learning_card_session.execute(
        select(func.count()).select_from(CardAudio)
    ).scalar_one()
    assert left == 0


def test_loading_a_recording_leaves_its_bytes_in_the_database(
    learning_card_session, recorded
):
    """Deferred, so nothing that loads a row drags the bytes along by accident."""
    learning_card_session.expunge_all()

    row = learning_card_session.get(CardAudio, recorded["id"])

    assert "audio" in inspect(row).unloaded
    assert row.source_text == recorded["sourceText"]
