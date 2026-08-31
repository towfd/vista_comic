"""The reader's scheduling settings (vocabulary stage 6, ticket 02).

One row for the whole deployment, which has no per-user identity to key on
(ADR-0005). It lives on the backend rather than on the device because the
backend recomputes schedules when an offline session flushes, and two copies
that disagreed would produce two different `dueAt` values for the same answer.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app import main, scheduler


@pytest.fixture
def client(learning_card_db):
    return TestClient(main.app)


def test_the_defaults_are_there_before_anyone_sets_them(client):
    """A settings screen must never open onto nothing.

    Seeded by the migration, and healed by the store if a database somehow
    arrives without the row — refusing to schedule would be a worse failure than
    scheduling on the defaults.
    """
    settings = client.get("/study/settings").json()

    assert settings["learningSteps"] == list(scheduler.DEFAULT_LEARNING_STEPS)
    assert settings["newCardsPerDay"] == scheduler.DEFAULT_NEW_CARDS_PER_DAY


def test_settings_round_trip(client):
    saved = client.put(
        "/study/settings", json={"learningSteps": [2, 9], "newCardsPerDay": 40}
    )

    assert saved.status_code == 200
    assert client.get("/study/settings").json() == {
        "learningSteps": [2, 9],
        "newCardsPerDay": 40,
    }


def test_the_number_of_steps_is_the_readers_too(client):
    """Not just the minutes.

    "How many steps" and "how long each step is" are the same question, which is
    why this is a list rather than three fields.
    """
    client.put(
        "/study/settings", json={"learningSteps": [1, 5, 15, 30], "newCardsPerDay": 15}
    )

    assert len(client.get("/study/settings").json()["learningSteps"]) == 4


def test_a_change_replaces_rather_than_merges(client):
    client.put(
        "/study/settings", json={"learningSteps": [1, 2, 3], "newCardsPerDay": 15}
    )
    client.put("/study/settings", json={"learningSteps": [4], "newCardsPerDay": 15})

    assert client.get("/study/settings").json()["learningSteps"] == [4]


@pytest.mark.parametrize(
    "body",
    [
        {"learningSteps": [], "newCardsPerDay": 15},
        {"learningSteps": [0, 5], "newCardsPerDay": 15},
        {"learningSteps": [5, -1], "newCardsPerDay": 15},
        {"learningSteps": [5], "newCardsPerDay": -1},
    ],
    ids=["no steps", "a zero step", "a negative step", "negative new cards"],
)
def test_settings_that_would_break_scheduling_are_refused(client, body):
    """An empty list has no first step to restart on, and a zero-minute step
    would schedule a card to be due before it was answered."""
    assert client.put("/study/settings", json=body).status_code == 422


def test_no_new_cards_a_day_is_allowed(client):
    """Zero is a choice, not a mistake: clear the backlog without meeting more."""
    assert (
        client.put(
            "/study/settings", json={"learningSteps": [5], "newCardsPerDay": 0}
        ).status_code
        == 200
    )


def test_the_settings_are_what_the_scheduler_actually_uses(client):
    """The point of storing them at all.

    A single one-minute step means the next correct answer graduates the card,
    which no default could produce.
    """
    client.put("/study/settings", json={"learningSteps": [1], "newCardsPerDay": 15})
    card_id = client.post(
        "/cards",
        json={
            "sourceText": "TRONG KHI",
            "translation": "當…的時候",
            "targetLanguage": "zh-Hant",
            "comicId": "deadbeefdeadbeef",
            "chapterId": "beefdeadbeefdead",
            "pageNumber": 1,
            "kind": "word",
        },
    ).json()["id"]

    def answer(token):
        return client.post(
            f"/cards/{card_id}/reviews",
            json={
                "questionType": "cloze_typed",
                "isCorrect": True,
                "clientToken": token,
                "localDate": "2026-08-31",
            },
        ).json()

    assert answer("a")["state"] == "learning"
    assert answer("b")["state"] == "review"
