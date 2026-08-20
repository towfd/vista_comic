"""Recording answers (vocabulary stage 4, ticket 01).

The property worth guarding is **idempotency**. Nothing in the app queues
reviews yet, but a tapped button on a slow connection is exactly how one answer
becomes two — and a duplicated wrong answer drops a rung the reader never lost,
silently, in a system whose whole job is to be trusted about what they know.
"""

from __future__ import annotations

from datetime import date

import pytest
from fastapi.testclient import TestClient

from app import card_review_store, main

_CARD = {
    "sourceText": "TRONG KHI",
    "translation": "當…的時候",
    "targetLanguage": "zh-Hant",
    "comicId": "deadbeefdeadbeef",
    "chapterId": "beefdeadbeefdead",
    "pageNumber": 1,
    "kind": "word",
}

_TODAY = "2026-08-20"

_REVIEW = {
    "questionType": "cloze_choice",
    "isCorrect": True,
    "clientToken": "token-1",
    "elapsedMs": 2400,
    "localDate": _TODAY,
}


@pytest.fixture
def client(learning_card_db):
    return TestClient(main.app)


@pytest.fixture
def card_id(client) -> int:
    return client.post("/cards", json=_CARD).json()["id"]


def _review(client, card_id, **overrides):
    return client.post(f"/cards/{card_id}/reviews", json={**_REVIEW, **overrides})


# --- recording ---------------------------------------------------------------


def test_an_answer_is_recorded(client, card_id):
    resp = _review(client, card_id)

    assert resp.status_code == 201, resp.text
    review = resp.json()["review"]
    assert review["cardId"] == card_id
    assert review["questionType"] == "cloze_choice"
    assert review["isCorrect"] is True
    assert review["elapsedMs"] == 2400
    assert review["reviewedAt"]


def test_elapsed_time_is_optional(client, card_id):
    """Read by nothing today. Kept because response time is what FSRS wants and
    cannot be collected retroactively."""
    resp = _review(client, card_id, elapsedMs=None)

    assert resp.status_code == 201
    assert resp.json()["review"]["elapsedMs"] is None


def test_a_wrong_answer_is_recorded_as_such(client, card_id):
    assert _review(client, card_id, isCorrect=False).json()["review"]["isCorrect"] is False


def test_an_unrecognised_question_type_is_refused(client, card_id):
    resp = _review(client, card_id, questionType="essay")

    assert resp.status_code == 422
    assert client.get(f"/cards/{card_id}/reviews").json() == []


def test_an_answer_for_a_card_that_is_gone_is_a_404(client):
    resp = client.post("/cards/999999/reviews", json=_REVIEW)

    assert resp.status_code == 404


# --- the property this ticket exists for -------------------------------------


def test_the_same_answer_submitted_twice_is_recorded_once(client, card_id):
    """A retry must not count twice.

    A duplicated wrong answer would drop a rung the reader never lost, and they
    would have no way to tell it had happened.
    """
    first = _review(client, card_id)
    second = _review(client, card_id)

    assert first.status_code == 201
    assert second.json()["review"]["id"] == first.json()["review"]["id"]
    assert len(client.get(f"/cards/{card_id}/reviews").json()) == 1


def test_two_genuinely_different_answers_are_both_recorded(client, card_id):
    """Idempotency must not swallow a real second answer — a card is asked more
    than once in a round, and passing the day depends on counting both."""
    _review(client, card_id, clientToken="token-1")
    _review(client, card_id, clientToken="token-2", isCorrect=False)

    assert len(client.get(f"/cards/{card_id}/reviews").json()) == 2


def test_the_store_keeps_one_row_under_a_racing_submission(learning_card_session):
    """The constraint, not the pre-check, is what makes the retry safe."""
    from app import learning_card_store

    card, _ = learning_card_store.create_or_get(
        learning_card_session,
        source_text="TRONG KHI",
        translation="當…的時候",
        target_language="zh-Hant",
        comic_id="c",
        chapter_id="ch",
        page_number=1,
    )
    common = dict(
        card_id=card.id,
        question_type=card_review_store.QUESTION_CLOZE_TYPED,
        is_correct=True,
        client_token="same",
        local_date=date(2026, 8, 20),
    )

    first, created_first = card_review_store.record(learning_card_session, **common)
    second, created_second = card_review_store.record(learning_card_session, **common)

    assert created_first is True
    assert created_second is False
    assert second.id == first.id


# --- reading them back -------------------------------------------------------


def test_reviews_come_back_oldest_first(client, card_id):
    """The order a day is replayed in. Newest-first would invert the three-step
    machine and quietly compute the wrong answer."""
    _review(client, card_id, clientToken="a", isCorrect=False)
    _review(client, card_id, clientToken="b", isCorrect=True)
    _review(client, card_id, clientToken="c", isCorrect=True)

    listed = client.get(f"/cards/{card_id}/reviews").json()

    assert [r["isCorrect"] for r in listed] == [False, True, True]


def test_reviews_for_an_unknown_card_are_a_404(client):
    assert client.get("/cards/999999/reviews").status_code == 404


def test_deleting_a_card_takes_its_reviews_with_it(client, card_id):
    """They describe a card. Once it is gone they describe nothing."""
    _review(client, card_id)

    client.delete(f"/cards/{card_id}")

    again = client.post("/cards", json=_CARD).json()["id"]
    assert client.get(f"/cards/{again}/reviews").json() == []


def test_one_cards_reviews_are_not_anothers(client):
    first = client.post("/cards", json=_CARD).json()["id"]
    second = client.post("/cards", json={**_CARD, "sourceText": "ĂN MÒN"}).json()["id"]

    _review(client, first, clientToken="a")

    assert len(client.get(f"/cards/{first}/reviews").json()) == 1
    assert client.get(f"/cards/{second}/reviews").json() == []


# --- what an answer does to the card (ticket 03) -----------------------------


def _answer(client, card_id, *, correct: bool, token: str, day: str = _TODAY):
    return client.post(
        f"/cards/{card_id}/reviews",
        json={
            "questionType": "cloze_typed",
            "isCorrect": correct,
            "clientToken": token,
            "localDate": day,
        },
    ).json()


def test_one_correct_answer_is_not_yet_a_pass(client, card_id):
    """Nothing has resolved. The card is climbing, not finished — and the rung
    must not move on a card the reader has answered once."""
    outcome = _answer(client, card_id, correct=True, token="a")

    assert outcome["step"] == "familiar"
    assert outcome["ladderMoved"] is False
    assert outcome["ladderStage"] == 0


def test_two_correct_answers_pass_the_day_and_advance_the_rung(client, card_id):
    _answer(client, card_id, correct=True, token="a")
    outcome = _answer(client, card_id, correct=True, token="b")

    assert outcome["step"] == "passed"
    assert outcome["ladderMoved"] is True
    assert outcome["ladderStage"] == 1
    assert outcome["dueOn"] == "2026-08-23"  # three days, the second interval


def test_a_wrong_answer_drops_to_the_bottom_and_is_due_tomorrow(client, card_id):
    for token in ("a", "b"):
        _answer(client, card_id, correct=True, token=token)
    # Now on rung 1. A new day, so the ladder can move again.
    outcome = _answer(client, card_id, correct=False, token="c", day="2026-08-21")

    assert outcome["ladderStage"] == 0
    assert outcome["dueOn"] == "2026-08-22"


def test_the_rung_moves_at_most_once_a_day(client, card_id):
    """The case that will feel unfair, and is deliberate.

    Answering wrong resolves the day. Drilling the card to 通過 an hour later
    still passes it *for the day* — but the ladder already recorded that the
    reader met this word and did not have it, and that is what it measures.
    """
    dropped = _answer(client, card_id, correct=False, token="a")
    assert dropped["ladderMoved"] is True
    assert dropped["ladderStage"] == 0

    _answer(client, card_id, correct=True, token="b")
    recovered = _answer(client, card_id, correct=True, token="c")

    assert recovered["step"] == "passed"
    assert recovered["ladderMoved"] is False
    assert recovered["ladderStage"] == 0


def test_passing_twice_in_one_day_moves_the_rung_once(client, card_id):
    for token in ("a", "b"):
        _answer(client, card_id, correct=True, token=token)
    again = _answer(client, card_id, correct=True, token="c")

    assert again["ladderStage"] == 1
    assert again["ladderMoved"] is False


def test_a_new_day_can_move_the_rung_again(client, card_id):
    for token in ("a", "b"):
        _answer(client, card_id, correct=True, token=token)

    _answer(client, card_id, correct=True, token="c", day="2026-08-21")
    outcome = _answer(client, card_id, correct=True, token="d", day="2026-08-21")

    assert outcome["ladderStage"] == 2


def test_yesterdays_answers_do_not_count_towards_today(client, card_id):
    """The day is replayed from the day's own rows.

    Without the date filter, a card answered correctly once yesterday and once
    today would pass — on two answers the reader gave a day apart.
    """
    _answer(client, card_id, correct=True, token="a", day="2026-08-19")
    outcome = _answer(client, card_id, correct=True, token="b", day="2026-08-20")

    assert outcome["step"] == "familiar"
    assert outcome["ladderMoved"] is False


def test_a_replayed_submission_cannot_move_the_rung_twice(client, card_id):
    """The two guards meet here: idempotency stops a second row, and the
    once-a-day rule stops a second move even if one appeared."""
    _answer(client, card_id, correct=True, token="a")
    first = _answer(client, card_id, correct=True, token="b")
    replay = _answer(client, card_id, correct=True, token="b")

    assert first["ladderStage"] == 1
    assert replay["ladderStage"] == 1
    assert replay["ladderMoved"] is False


def test_a_listed_review_says_nothing_about_the_card(client, card_id):
    """A step or a rung on a row from last week would be describing the card,
    not the answer — so the list carries neither."""
    _answer(client, card_id, correct=True, token="a")

    row = client.get(f"/cards/{card_id}/reviews").json()[0]

    assert "step" not in row
    assert "ladderStage" not in row
