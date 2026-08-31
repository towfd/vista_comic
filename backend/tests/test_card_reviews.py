"""Recording answers (vocabulary stage 4, ticket 01).

The property worth guarding is **idempotency**. Nothing in the app queues
reviews yet, but a tapped button on a slow connection is exactly how one answer
becomes two — and a duplicated wrong answer drops a rung the reader never lost,
silently, in a system whose whole job is to be trusted about what they know.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

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
        answered_at=datetime.now(timezone.utc),
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


def _answer(
    client,
    card_id,
    *,
    correct: bool,
    token: str,
    day: str = _TODAY,
    context: str | None = None,
    answered_at: str | None = None,
):
    body = {
        "questionType": "cloze_typed",
        "isCorrect": correct,
        "clientToken": token,
        "localDate": day,
    }
    # Omitted rather than sent explicitly when unset, so the default path — the
    # one an older build takes — is what most of these tests exercise.
    if context is not None:
        body["context"] = context
    if answered_at is not None:
        body["answeredAt"] = answered_at
    return client.post(f"/cards/{card_id}/reviews", json=body).json()


def _due_in_days(outcome, days: int) -> bool:
    """Whether the endpoint scheduled the card roughly `days` out.

    Compared loosely because `dueAt` is a timestamp now: the answer's own moment
    plus the interval, which is only equal to a date boundary by accident.
    """
    due = datetime.fromisoformat(outcome["dueAt"])
    expected = datetime.now(timezone.utc) + timedelta(days=days)
    return abs((due - expected).total_seconds()) < 300


def test_a_first_answer_puts_the_card_into_the_learning_steps(client, card_id):
    """No slot has been earned yet — the card is minutes away, not days."""
    outcome = _answer(client, card_id, correct=True, token="a")

    assert outcome["state"] == "learning"
    assert outcome["intervalChanged"] is False
    assert outcome["ladderStage"] == 0


def test_meeting_a_card_records_the_day_it_stopped_being_new(client, card_id):
    """What the daily new-card quota counts, in the reader's day.

    It cannot be derived from the log: the stage 6 migration resets cards while
    keeping their answers, so a card's oldest answer is not when it was met.
    """
    assert client.get("/cards").json()[0]["introducedOn"] is None

    outcome = _answer(client, card_id, correct=True, token="a", day="2026-08-31")
    assert outcome["introducedOn"] == "2026-08-31"


def test_the_day_a_card_was_met_does_not_move_afterwards(client, card_id):
    """Otherwise a card answered again tomorrow would spend tomorrow's quota."""
    _answer(client, card_id, correct=True, token="a", day="2026-08-30")
    outcome = _answer(client, card_id, correct=False, token="b", day="2026-08-31")

    assert outcome["introducedOn"] == "2026-08-30"


def test_a_training_answer_does_not_introduce_a_card(client, card_id):
    """Training draws from cards already met, so this should not arise — and if
    it does, spending the quota on an answer that schedules nothing would be the
    worst of both."""
    outcome = _answer(client, card_id, correct=True, token="a", context="training")

    assert outcome["introducedOn"] is None
    assert outcome["state"] == "new"


def test_a_first_answer_that_is_wrong_also_only_reaches_the_first_step(
    client, card_id
):
    """There is nothing below the bottom, and a first encounter is often wrong.

    Under the ladder this replaced, this same answer sealed the card for the
    whole day — which is why a fresh deck could never climb at all.
    """
    outcome = _answer(client, card_id, correct=False, token="a")

    assert outcome["state"] == "learning"
    assert outcome["ladderStage"] == 0


def test_four_correct_answers_graduate_the_card(client, card_id):
    """One to meet it, then one per step.

    The first answer only *enters* the steps — 5 minutes — which is what the
    reader described: right the first time is five minutes, then seven, then
    ten, and the fourth is where the interval table starts.
    """
    for token in ("a", "b", "c"):
        assert _answer(client, card_id, correct=True, token=token)["state"] == "learning"
    outcome = _answer(client, card_id, correct=True, token="d")

    assert outcome["state"] == "review"
    assert outcome["intervalChanged"] is True
    assert outcome["ladderStage"] == 0
    assert _due_in_days(outcome, 1)


def test_a_wrong_answer_restarts_the_steps_without_touching_the_slot(
    client, card_id
):
    for token in ("a", "b"):
        _answer(client, card_id, correct=True, token=token)
    outcome = _answer(client, card_id, correct=False, token="c")

    assert outcome["state"] == "learning"
    assert outcome["intervalChanged"] is False
    assert outcome["ladderStage"] == 0


def test_a_card_answered_wrong_can_still_graduate_the_same_day(client, card_id):
    """The recovery the old lock made impossible.

    A fresh deck is cards on the bottom slot and first encounters are mostly
    wrong; the lock meant nothing ever climbed, and the question types that live
    higher up were unreachable. Falling and climbing back now costs minutes.
    """
    _answer(client, card_id, correct=False, token="a")
    for token in ("b", "c"):
        _answer(client, card_id, correct=True, token=token)
    outcome = _answer(client, card_id, correct=True, token="d")

    assert outcome["state"] == "review"
    assert outcome["ladderStage"] == 0


def test_a_graduated_card_missed_falls_one_slot_not_to_the_bottom(client, card_id):
    """Sixty days does not become one.

    Judging is an exact match on production, so a wrong answer is often a slip
    rather than a forgetting, and charging the whole table for it teaches
    nothing. Getting to slot 2 takes six correct answers — four to graduate onto
    slot 0, then one per slot — which is what the loop below is doing.
    """
    token = iter("abcdefghijklmnop")
    for _ in range(6):
        outcome = _answer(client, card_id, correct=True, token=next(token))
    assert outcome["ladderStage"] == 2

    lapsed = _answer(client, card_id, correct=False, token=next(token))
    assert lapsed["state"] == "relearning"

    for _ in range(3):
        recovered = _answer(client, card_id, correct=True, token=next(token))
    assert recovered["state"] == "review"
    assert recovered["ladderStage"] == 1
    assert _due_in_days(recovered, 3)


def test_a_graduated_card_climbs_on_every_correct_answer(client, card_id):
    """**What stops this being drilling is the queue, not the scheduler.**

    The ladder this replaced refused to move on an answer that changed no step,
    which is how it kept ten correct answers in one round from carrying a card
    to the top. There is no resting place to sit in now, so the endpoint moves
    the card every time it is asked — and what keeps that honest is that a
    graduated card is scheduled a day out and the round will not offer it again
    (stage 6 ticket 03). Training answers, which could, schedule nothing.
    """
    token = iter("abcdefghijklmnop")
    for _ in range(4):
        _answer(client, card_id, correct=True, token=next(token))

    for expected in (1, 2, 3):
        outcome = _answer(client, card_id, correct=True, token=next(token))
        assert outcome["ladderStage"] == expected
        assert outcome["intervalChanged"] is True


def test_the_top_slot_clamps_rather_than_overflowing(client, card_id):
    token = iter("abcdefghijklmnopqrstuvwxyz")
    for _ in range(20):
        outcome = _answer(client, card_id, correct=True, token=next(token))

    assert outcome["ladderStage"] == 6
    assert _due_in_days(outcome, 365)


def test_a_gap_of_days_does_not_reset_the_learning_steps(client, card_id):
    """The whole point of storing the state.

    Three answers yesterday and one today graduate the card. Under the
    three-step day the three would have expired at midnight, and the reader
    would have been starting again every morning without being told why.
    """
    for token in ("a", "b", "c"):
        _answer(client, card_id, correct=True, token=token, day="2026-08-19")
    outcome = _answer(client, card_id, correct=True, token="d", day="2026-08-20")

    assert outcome["state"] == "review"


def test_a_replayed_submission_cannot_move_the_card_twice(client, card_id):
    """The only guard, and it is the one that has to hold.

    A replay stores no row, so the endpoint does not even attempt a move.
    """
    for token in ("a", "b", "c"):
        _answer(client, card_id, correct=True, token=token)
    first = _answer(client, card_id, correct=True, token="d")
    replay = _answer(client, card_id, correct=True, token="d")

    assert first["state"] == "review"
    assert first["ladderStage"] == 0
    assert replay["ladderStage"] == 0
    assert replay["intervalChanged"] is False


def test_a_listed_review_says_nothing_about_the_card(client, card_id):
    """A step or a rung on a row from last week would be describing the card,
    not the answer — so the list carries neither."""
    _answer(client, card_id, correct=True, token="a")

    row = client.get(f"/cards/{card_id}/reviews").json()[0]

    assert "step" not in row
    assert "ladderStage" not in row


def test_the_two_sentence_question_types_are_accepted(client, card_id):
    """Stage 5 adds producing the whole sentence, typed or rearranged.

    Recorded distinctly rather than folded into the cloze types, because what
    was asked is not recoverable afterwards if it was never written down — and
    anything that later weighs difficulty will want it.
    """
    for token, kind in [("a", "sentence_typed"), ("b", "sentence_rearranged")]:
        resp = client.post(
            f"/cards/{card_id}/reviews",
            json={
                "questionType": kind,
                "isCorrect": True,
                "clientToken": token,
                "localDate": _TODAY,
            },
        )
        assert resp.status_code == 201, resp.text
        assert resp.json()["review"]["questionType"] == kind


def test_the_question_type_does_not_change_what_an_answer_does(client, card_id):
    """The scheduler counts answers, not question types.

    A card produced correctly three times has been recalled three times,
    whichever way it was asked — which is what lets stage 6 draw the mode at
    random.
    """
    for token, kind in (
        ("a", "sentence_typed"),
        ("b", "sentence_rearranged"),
        ("c", "cloze_choice"),
        ("d", "cloze_typed"),
    ):
        outcome = client.post(
            f"/cards/{card_id}/reviews",
            json={
                "questionType": kind,
                "isCorrect": True,
                "clientToken": token,
                "localDate": _TODAY,
            },
        ).json()

    assert outcome["state"] == "review"
    assert outcome["ladderStage"] == 0


def test_a_training_answer_is_recorded_and_schedules_nothing(client, card_id):
    """永無止盡的訓練 exists to be practised in without consequences.

    The reader chose this against the objection that a card forgotten in
    training is evidence the schedule is wrong and is being thrown away. The
    answer is still a fact and still belongs in the log.
    """
    _answer(client, card_id, correct=True, token="a", context="training")
    outcome = _answer(client, card_id, correct=True, token="b", context="training")

    assert outcome["state"] == "new"
    assert outcome["learningStep"] is None
    assert outcome["intervalChanged"] is False
    assert outcome["ladderStage"] == 0

    # And the answers themselves are all there: the log stays complete.
    listed = client.get(f"/cards/{card_id}/reviews").json()
    assert len(listed) == 2


def test_a_training_answer_cannot_drop_a_card_either(client, card_id):
    """Both directions, because the reason is about evidence, not about mercy."""
    for token in ("a", "b", "c", "d"):
        _answer(client, card_id, correct=True, token=token)
    outcome = _answer(client, card_id, correct=False, token="e", context="training")

    assert outcome["state"] == "review"
    assert outcome["intervalChanged"] is False
    assert outcome["ladderStage"] == 0


def test_an_answer_with_no_context_is_a_review(client, card_id):
    """The default an app that says nothing gets, pinned so it cannot drift."""
    for token in ("a", "b", "c"):
        _answer(client, card_id, correct=True, token=token)
    outcome = _answer(client, card_id, correct=True, token="d")

    assert outcome["intervalChanged"] is True
    assert outcome["state"] == "review"


def test_an_unrecognised_context_is_refused(client, card_id):
    resp = client.post(
        f"/cards/{card_id}/reviews",
        json={
            "questionType": "cloze_typed",
            "isCorrect": True,
            "clientToken": "a",
            "localDate": _TODAY,
            "context": "whatever",
        },
    )
    assert resp.status_code == 422


def test_the_answer_time_is_taken_from_the_app_not_the_clock(client, card_id):
    """The property offline practice rests on.

    An answer given in airplane mode this morning and flushed this evening must
    be scheduled from this morning. Sent here as a timestamp hours in the past,
    and the card's next due time has to follow it rather than now.
    """
    long_ago = datetime.now(timezone.utc) - timedelta(hours=6)
    outcome = _answer(
        client, card_id, correct=True, token="a", answered_at=long_ago.isoformat()
    )

    due = datetime.fromisoformat(outcome["dueAt"])
    assert abs((due - (long_ago + timedelta(minutes=5))).total_seconds()) < 5
    assert due < datetime.now(timezone.utc)


def test_the_answer_time_is_stored_as_given(client, card_id):
    """`answeredAt` and `reviewedAt` are two different facts and both are kept."""
    long_ago = datetime.now(timezone.utc) - timedelta(hours=6)
    _answer(client, card_id, correct=True, token="a", answered_at=long_ago.isoformat())

    with main._card_session() as session:
        rows = card_review_store.for_card(session, card_id)
    assert abs((rows[0].answered_at - long_ago).total_seconds()) < 5
    assert rows[0].reviewed_at > long_ago + timedelta(hours=5)
