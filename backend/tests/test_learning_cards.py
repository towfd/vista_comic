"""Learning card store + endpoint tests (vocabulary-review stage 1, ticket 01).

Runs against the throwaway Postgres database (see ``conftest.py``), with
``learning_card`` truncated before each test.

The normalisation vector table below is **shared verbatim with the Swift
suite** (ticket 03) and with the spec at
``.scratch/vocabulary-review/01-card-storage/spec.md``. It is the guard on the
one rule this feature implements twice: if the two sides disagree, the app
reports "not collected" while the server reports "duplicate", and the reader
sees an add button that never seems to finish anything.

No fixture library or catalog is needed: like the comprehension routes, these
take an opaque source reference without validating it.
"""

from __future__ import annotations

from datetime import date, datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app import learning_card_store, main
from app.normalization import normalized_key

_BODY = {
    "sourceText": "大丈夫ですか",
    "translation": "你還好嗎",
    "targetLanguage": "zh-Hant",
    "comicId": "deadbeefdeadbeef",
    "chapterId": "beefdeadbeefdead",
    "pageNumber": 12,
}

# Input -> expected key. Copied into `spec.md` and into the Swift tests; change
# all three together or not at all.
NORMALISATION_VECTORS = [
    ("大丈夫\nですか", "大丈夫ですか"),
    ("　大丈夫ですか　", "大丈夫ですか"),
    ("ﾀﾞｲｼﾞｮｳﾌﾞ", "ダイジョウブ"),
    ("Good  Morning", "goodmorning"),
    ("good morning", "goodmorning"),
    ("食べた", "食べた"),
    ("食べる", "食べる"),
    ("   ", ""),
]


@pytest.fixture
def client(learning_card_db):
    return TestClient(main.app)


def _add(client, **overrides):
    return client.post("/cards", json={**_BODY, **overrides})


# --- the rule the app has to agree with -------------------------------------


@pytest.mark.parametrize("text,expected", NORMALISATION_VECTORS)
def test_normalisation_matches_the_shared_vector_table(text, expected):
    assert normalized_key(text) == expected


def test_inflected_forms_are_deliberately_separate():
    """Not a limitation to be fixed later — see ``app/normalization.py``.

    A form the reader can already read is never collected again, so a form that
    keeps coming back is one they keep failing, and that repetition is the
    signal worth keeping per form.
    """
    assert normalized_key("食べた") != normalized_key("食べる")


# --- collecting --------------------------------------------------------------


def test_adding_a_line_returns_it_as_a_new_card(client):
    resp = _add(client)

    assert resp.status_code == 201, resp.text
    card = resp.json()
    assert card["sourceText"] == _BODY["sourceText"]
    assert card["translation"] == _BODY["translation"]
    assert card["targetLanguage"] == _BODY["targetLanguage"]
    assert card["comicId"] == _BODY["comicId"]
    assert card["pageNumber"] == 12
    # Written now, read in stage 3.
    assert card["ladderStage"] == learning_card_store.INITIAL_LADDER_STAGE
    assert card["dueOn"]
    # Only re-lookups move this, and none has happened.
    assert card["lookupCount"] == 0
    assert card["lastLookedUpAt"] is None


def test_adding_the_same_line_twice_returns_the_same_card_with_200(client):
    """The offline queue replays blindly; a replay must not be an error."""
    first = _add(client)
    second = _add(client)

    assert first.status_code == 201
    assert second.status_code == 200, second.text
    assert second.json()["id"] == first.json()["id"]
    assert len(client.get("/cards").json()) == 1


def test_line_breaks_and_width_do_not_make_a_second_card(client):
    """The OCR carries a speech bubble's line breaks in. Same word regardless."""
    _add(client, sourceText="大丈夫ですか")
    again = _add(client, sourceText="大丈夫\nですか")

    assert again.status_code == 200
    assert len(client.get("/cards").json()) == 1


def test_the_same_word_in_another_language_is_another_card(client):
    """Identity is the key *and* the target language."""
    _add(client)
    other = _add(client, targetLanguage="en")

    assert other.status_code == 201
    assert len(client.get("/cards").json()) == 2


def test_the_same_word_from_another_comic_is_the_same_card(client):
    """The comic is deliberately not part of a card's identity.

    Splitting by source would fragment the lookup count that stage 3 reads as a
    forgetting signal.
    """
    first = _add(client)
    elsewhere = _add(client, comicId="ffffffffffffffff", chapterId="1111111111111111")

    assert elsewhere.status_code == 200
    assert elsewhere.json()["id"] == first.json()["id"]


def test_the_store_returns_the_existing_card_for_an_equivalent_line(
    learning_card_session,
):
    """Two spellings of one word reach the same row through the pre-check."""
    common = dict(
        translation="你還好嗎",
        target_language="zh-Hant",
        comic_id="deadbeefdeadbeef",
        chapter_id="beefdeadbeefdead",
        page_number=12,
    )
    first, created_first = learning_card_store.create_or_get(
        learning_card_session, source_text="大丈夫ですか", **common
    )
    second, created_second = learning_card_store.create_or_get(
        learning_card_session, source_text="　大丈夫ですか", **common
    )

    assert created_first is True
    assert created_second is False
    assert second.id == first.id


def test_the_constraint_refuses_a_second_row_for_one_identity(learning_card_session):
    """The pre-check is a convenience; **this** is what makes it safe.

    Two requests can both miss the pre-check and race to insert. The store
    catches the resulting ``IntegrityError`` and reads back the winner, which is
    only correct because the database refuses the loser — asserted here directly
    rather than inferred from the store's behaviour.
    """
    from sqlalchemy.exc import IntegrityError

    from app.db import LearningCard

    common = dict(
        source_text="大丈夫ですか",
        translation="你還好嗎",
        target_language="zh-Hant",
        comic_id="deadbeefdeadbeef",
        chapter_id="beefdeadbeefdead",
        page_number=12,
    )
    learning_card_store.create_or_get(learning_card_session, **common)

    learning_card_session.add(
        LearningCard(
            normalized_key=normalized_key(common["source_text"]),
            ladder_stage=0,
            due_on=date.today(),
            lookup_count=0,
            created_at=datetime.now(timezone.utc),
            **common,
        )
    )
    with pytest.raises(IntegrityError):
        learning_card_session.commit()
    learning_card_session.rollback()


def test_an_archived_card_is_revived_rather_than_shadowed(learning_card_session):
    """Otherwise add would say "collected" about a card no list ever shows."""
    common = dict(
        source_text="大丈夫ですか",
        translation="你還好嗎",
        target_language="zh-Hant",
        comic_id="deadbeefdeadbeef",
        chapter_id="beefdeadbeefdead",
        page_number=12,
    )
    card, _ = learning_card_store.create_or_get(learning_card_session, **common)
    card.archived_at = datetime.now(timezone.utc)
    learning_card_session.commit()

    again, created = learning_card_store.create_or_get(learning_card_session, **common)

    assert created is False
    assert again.archived_at is None
    assert learning_card_store.list_active(learning_card_session) != []


# --- what is refused ---------------------------------------------------------


def test_a_whole_page_of_text_is_refused(client):
    """A guard against a stray selection, not a feature."""
    resp = _add(client, sourceText="あ" * (learning_card_store.MAX_SOURCE_TEXT_LENGTH + 1))

    assert resp.status_code == 422
    assert client.get("/cards").json() == []


def test_a_line_at_the_cap_is_accepted(client):
    resp = _add(client, sourceText="あ" * learning_card_store.MAX_SOURCE_TEXT_LENGTH)

    assert resp.status_code == 201


def test_text_that_normalises_to_nothing_is_refused(client):
    """The length cap cannot catch a string of spaces, and an empty identity
    would collide with every other empty one."""
    resp = _add(client, sourceText="   \n　 ")

    assert resp.status_code == 422
    assert client.get("/cards").json() == []


def test_an_empty_source_is_refused(client):
    assert _add(client, sourceText="").status_code == 422


# --- listing -----------------------------------------------------------------


def test_cards_come_back_newest_first(client):
    _add(client, sourceText="ひとつ")
    _add(client, sourceText="ふたつ")
    _add(client, sourceText="みっつ")

    listed = [c["sourceText"] for c in client.get("/cards").json()]

    assert listed == ["みっつ", "ふたつ", "ひとつ"]


def test_archived_cards_are_left_out_of_the_list(client, learning_card_session):
    from sqlalchemy import select

    from app.db import LearningCard

    kept = _add(client, sourceText="ひとつ").json()
    _add(client, sourceText="ふたつ")

    hidden = learning_card_session.execute(
        select(LearningCard).where(LearningCard.source_text == "ふたつ")
    ).scalar_one()
    hidden.archived_at = datetime.now(timezone.utc)
    learning_card_session.commit()

    listed = client.get("/cards").json()

    assert [c["id"] for c in listed] == [kept["id"]]


# --- looking a collected word up again ---------------------------------------


def test_a_lookup_is_counted_and_stamped(client):
    card = _add(client).json()

    assert client.post(f"/cards/{card['id']}/lookups").status_code == 204
    assert client.post(f"/cards/{card['id']}/lookups").status_code == 204

    updated = client.get("/cards").json()[0]
    assert updated["lookupCount"] == 2
    assert updated["lastLookedUpAt"] is not None


def test_a_lookup_does_not_touch_the_schedule(client):
    """Rescheduling on a hit belongs to stage 3, where scheduling exists."""
    card = _add(client).json()

    client.post(f"/cards/{card['id']}/lookups")

    updated = client.get("/cards").json()[0]
    assert updated["dueOn"] == card["dueOn"]
    assert updated["ladderStage"] == card["ladderStage"]


def test_a_lookup_for_a_card_that_is_gone_is_a_404(client):
    """The app drops a 4xx from its queue rather than retrying it forever."""
    assert client.post("/cards/999999/lookups").status_code == 404


# --- word or sentence, said by the reader (ticket 06) -----------------------


def test_a_card_records_which_button_was_pressed(client):
    word = _add(client, sourceText="ひとつ", kind="word").json()
    sentence = _add(client, sourceText="ふたつ", kind="sentence").json()

    assert word["kind"] == "word"
    assert sentence["kind"] == "sentence"


def test_a_card_collected_without_a_kind_has_none(client):
    """Never guessed. A client that does not say leaves it unanswered."""
    assert _add(client).json()["kind"] is None


def test_an_unrecognised_kind_is_refused(client):
    """It would reach stage 3 as a card no question type knows how to ask
    about, which is worse than refusing it here."""
    resp = _add(client, sourceText="みっつ", kind="paragraph")

    assert resp.status_code == 422
    assert client.get("/cards").json() == []


def test_collecting_under_the_other_button_leaves_the_kind_alone(client):
    """Re-collecting is not a correction.

    The system does not silently rewrite something the reader already approved
    — the same rule the stored translation follows. 單字庫 is where a mis-tap
    gets fixed.
    """
    first = _add(client, kind="word").json()

    again = _add(client, kind="sentence")

    assert again.status_code == 200
    assert again.json()["id"] == first["id"]
    assert again.json()["kind"] == "word"
    assert len(client.get("/cards").json()) == 1


def test_kind_is_not_part_of_a_cards_identity(client):
    """Otherwise the library would hold two visually identical rows, and the
    lookup count that stages 3 and 4 read would be split across them."""
    _add(client, kind="word")
    _add(client, kind="sentence")

    assert len(client.get("/cards").json()) == 1


# --- fixing a card (spec-02 ticket 01) --------------------------------------


def test_the_translation_can_be_corrected(client):
    card = _add(client).json()

    resp = client.patch(f"/cards/{card['id']}", json={"translation": "你沒事吧"})

    assert resp.status_code == 200, resp.text
    assert resp.json()["translation"] == "你沒事吧"
    assert client.get("/cards").json()[0]["translation"] == "你沒事吧"


def test_the_kind_can_be_set_changed_and_cleared(client):
    """Clearing matters: a card collected before the two buttons has no kind,
    and a mis-tap is corrected here because re-collecting leaves it alone."""
    card = _add(client).json()
    assert card["kind"] is None

    assert client.patch(f"/cards/{card['id']}", json={"kind": "word"}).json()["kind"] == "word"
    assert client.patch(f"/cards/{card['id']}", json={"kind": "sentence"}).json()["kind"] == "sentence"
    assert client.patch(f"/cards/{card['id']}", json={"kind": None}).json()["kind"] is None


def test_a_patch_that_changes_nothing_is_refused(client):
    """A client bug should surface as an error, not as a save that quietly did
    not happen."""
    card = _add(client).json()

    assert client.patch(f"/cards/{card['id']}", json={}).status_code == 422


def test_a_patch_cannot_move_the_cards_identity(client):
    """The columns that decide *which card this is* are not the client's.

    Asserted rather than assumed: the failure this guards against is a field
    silently accepted, which no amount of reading the handler would reveal.
    """
    card = _add(client).json()

    client.patch(
        f"/cards/{card['id']}",
        json={
            "translation": "你沒事吧",
            "sourceText": "まったく違う",
            "targetLanguage": "en",
            "comicId": "somewhere-else",
            "pageNumber": 999,
        },
    )

    after = client.get("/cards").json()[0]
    assert after["sourceText"] == _BODY["sourceText"]
    assert after["targetLanguage"] == _BODY["targetLanguage"]
    assert after["comicId"] == _BODY["comicId"]
    assert after["pageNumber"] == _BODY["pageNumber"]


def test_a_patch_leaves_the_reviewing_columns_alone(client):
    """Scheduling is stage 3's business, and the lookup count is evidence."""
    card = _add(client).json()
    client.post(f"/cards/{card['id']}/lookups")

    client.patch(f"/cards/{card['id']}", json={"translation": "你沒事吧"})

    after = client.get("/cards").json()[0]
    assert after["ladderStage"] == card["ladderStage"]
    assert after["dueOn"] == card["dueOn"]
    assert after["lookupCount"] == 1
    assert after["createdAt"] == card["createdAt"]


def test_an_unrecognised_kind_is_refused_on_patch(client):
    card = _add(client).json()

    assert client.patch(f"/cards/{card['id']}", json={"kind": "paragraph"}).status_code == 422


def test_an_empty_translation_is_refused(client):
    card = _add(client).json()

    assert client.patch(f"/cards/{card['id']}", json={"translation": ""}).status_code == 422


def test_patching_a_card_that_is_gone_is_a_404(client):
    assert client.patch("/cards/999999", json={"translation": "x"}).status_code == 404


def test_a_card_can_be_deleted(client):
    card = _add(client).json()

    assert client.delete(f"/cards/{card['id']}").status_code == 204
    assert client.get("/cards").json() == []


def test_deleting_twice_is_a_404(client):
    card = _add(client).json()

    client.delete(f"/cards/{card['id']}")

    assert client.delete(f"/cards/{card['id']}").status_code == 404


def test_a_deleted_line_can_be_collected_again_as_a_new_card(client):
    """A real delete, so nothing lingers to be revived — the new card starts
    from zero, which is the honest answer after the old one was thrown away."""
    first = _add(client).json()
    client.post(f"/cards/{first['id']}/lookups")
    client.delete(f"/cards/{first['id']}")

    again = _add(client)

    assert again.status_code == 201
    assert again.json()["id"] != first["id"]
    assert again.json()["lookupCount"] == 0
