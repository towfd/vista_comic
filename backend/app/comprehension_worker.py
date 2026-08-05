"""Background worker that turns pending comprehension records into explanations.

The record row *is* the queue (see ``db.ComprehensionRecord``). This module owns
*when* work runs; ``comprehension_store`` owns the SQL that claims and completes
it.

Two deliberate shapes, both from `comprehension-response-ux` ticket 07:

**A plain daemon thread, not an asyncio task.** This backend is entirely
synchronous -- SQLAlchemy sessions over psycopg -- so an asyncio worker would
have to hop every database call into a thread anyway, introducing the codebase's
first sync/async seam purely as an artifact of how the loop was started. A thread
leaves that question absent rather than displaced.

**All the logic lives in ``process_pending``, which is synchronous and callable
directly.** The thread is a loop around it holding nothing worth testing, so
worker tests need no threads, no sleeps and no waiting.

The work itself never leaves the backend: the page image is re-read from the
library on disk using the ids already on the row, downscaled here, and sent to
Claude. No image is ever stored, and the selection crop is not reconstructed --
a call deferred by minutes cannot have one, so every request is page-only.
"""

from __future__ import annotations

import base64
import io
import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Callable, Optional

import anthropic
from PIL import Image
from sqlalchemy.exc import SQLAlchemyError

from sqlalchemy.orm import Session

from . import comprehend_usage_store, comprehension_client, comprehension_store
from .db import ComprehensionRecord, new_session

logger = logging.getLogger("vista_comic.worker")

# How many records may be in flight at once.
#
# This bounds **Claude spend**, not thread pressure: at this scale (one reader,
# a handful of concurrent page-image requests, a default thread pool of 40)
# thread contention does not bite, and the only thing worth capping is how fast
# a runaway retry loop could burn the daily quota. Strictly serial was rejected
# because a reader who selects three passages on one page would otherwise wait
# three times as long for the last one.
#
# A tunable constant, not a load-bearing design premise -- 3 is reasoned, not
# measured, and nothing breaks if it changes.
MAX_CONCURRENT_JOBS = 3

# How long the loop sleeps when it finds nothing to do. Short enough that a
# record enqueued while the queue is idle starts promptly, long enough that an
# idle backend is not polling Postgres continuously.
POLL_INTERVAL_SECONDS = 2.0

# The long edge, in pixels, every page image is downscaled to before it is sent.
#
# This used to happen on the client, which no longer uploads anything. Claude
# bills images at roughly (width x height) / 750 tokens, so sending a raw manga
# scan instead of a downscaled one costs several times more per call and risks
# the model's own size limits.
PAGE_IMAGE_LONG_EDGE = 1024

# JPEG quality for the downscaled page. Matches what the iOS client used.
_JPEG_QUALITY = 80


def downscale_to_jpeg_base64(image_bytes: bytes, *, long_edge: int) -> str:
    """Downscale an image to ``long_edge`` and return base64-encoded JPEG.

    Never upscales: an image already at or under the target is re-encoded at its
    own size rather than blown up, which would cost tokens for no extra detail.

    Converted to RGB because the library may hold PNGs with alpha, and JPEG
    cannot encode an alpha channel.
    """
    with Image.open(io.BytesIO(image_bytes)) as image:
        image = image.convert("RGB")
        width, height = image.size
        longest = max(width, height)
        if longest > long_edge:
            scale = long_edge / longest
            image = image.resize(
                (round(width * scale), round(height * scale)), Image.LANCZOS
            )
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", quality=_JPEG_QUALITY)
    return base64.b64encode(buffer.getvalue()).decode()


class PageImageUnavailable(Exception):
    """The record's source page could not be read from the library.

    Its own type because it means the request never reached Claude, which is the
    condition for giving the reservation back.
    """


def _page_image_base64(
    record: ComprehensionRecord,
    page_path_for: Callable[..., Optional[Path]],
) -> str:
    """Read and downscale the record's source page, or raise ``PageImageUnavailable``.

    The page is located from the ids already on the row, which is the whole
    reason no image has to be stored: the library is the only copy and it is
    always re-derivable.

    Decoding is inside the same guard as reading, because a corrupt or
    non-image file fails just as ordinarily as a missing one -- and letting it
    escape would leave the record stuck in ``running`` until the next restart.

    A path escaping the library root is **not** ordinary: ``_safe_file`` raises
    for that, and it is re-raised as unavailable only after being logged at
    error level, so a containment failure is visible rather than silently
    indistinguishable from a deleted comic.
    """
    try:
        path = page_path_for(record.comic_id, record.chapter_id, record.page_number)
    except Exception as error:  # noqa: BLE001 -- includes _safe_file's containment refusal
        logger.error(
            "Comprehension record %s: refused to resolve its source page.",
            record.id,
            exc_info=True,
        )
        raise PageImageUnavailable(str(error)) from error
    if path is None:
        raise PageImageUnavailable(
            f"page {record.page_number} of {record.comic_id}/{record.chapter_id}"
        )
    try:
        image_bytes = path.read_bytes()
    except OSError as error:
        raise PageImageUnavailable(str(error)) from error
    try:
        return downscale_to_jpeg_base64(image_bytes, long_edge=PAGE_IMAGE_LONG_EDGE)
    except Exception as error:  # noqa: BLE001 -- corrupt/unsupported image, same outcome
        raise PageImageUnavailable(str(error)) from error


def _fail(
    session,
    record: ComprehensionRecord,
    *,
    refund: bool,
    reason: str,
) -> None:
    """Mark one record ``failed``, refunding only if Claude was never reached.

    One place makes that call, so the rule stays checkable: **the reservation
    comes back only when nothing was billed.** Getting it wrong in either
    direction is expensive -- refunding a billed request understates real spend
    on the only guard against a runaway loop, and not refunding an unissued one
    quietly drains the daily budget for work that never happened.
    """
    logger.warning("Comprehension record %s failed: %s", record.id, reason, exc_info=True)
    comprehension_store.mark_terminal(
        session, record.id, status=comprehension_store.STATUS_FAILED
    )
    if refund:
        comprehend_usage_store.refund(session, usage_date=record.usage_date)


def run_record(
    session,
    record: ComprehensionRecord,
    *,
    page_path_for: Callable[..., Optional[Path]],
) -> None:
    """Run one claimed record to a terminal status.

    The three outcomes are deliberately distinct, because they mean different
    things to the reader and offer different actions:

    - a result          -> ``ok``, with the cloud translation and three notes
    - Claude declined   -> ``declined``, and no retry will be offered
    - anything else     -> ``failed``, and a retry is offered

    The reservation is given back **only** when the request never reached
    Claude. The exception ladder below exists entirely to draw that line
    accurately; see each branch for why it falls on the side it does.
    """
    try:
        page_base64 = _page_image_base64(record, page_path_for)
    except PageImageUnavailable as error:
        # Nothing was sent, so nothing was billed.
        _fail(session, record, refund=True, reason=f"source page unavailable: {error}")
        return

    try:
        result = comprehension_client.comprehend(
            page_image_base64=page_base64,
            source_text=record.source_text,
            target_language_code=record.target_language,
            use_stronger_model=record.use_stronger_model,
        )
    except anthropic.APITimeoutError:
        # Caught BEFORE APIConnectionError, which it subclasses. A timeout means
        # the request DID reach Claude and was billed -- it just took too long
        # to answer -- so refunding it would understate real spend. This ordering
        # is load-bearing, not stylistic.
        _fail(session, record, refund=False, reason="Claude timed out")
        return
    except anthropic.APIConnectionError:
        # Genuinely never arrived: DNS, TLS, refused connection. Nothing billed.
        _fail(session, record, refund=True, reason="could not reach Claude")
        return
    except RuntimeError as error:
        # Raised by the API-key lookup before any client is constructed (see
        # config.get_claude_api_key), so no request was issued. Without this
        # branch a misconfigured container would burn one reservation per drain
        # while never calling anything.
        _fail(session, record, refund=True, reason=f"not configured to call Claude: {error}")
        return
    except Exception:  # noqa: BLE001 -- one failed record must not stop the queue
        # Everything else reached Claude and came back wrong (4xx/5xx, a
        # malformed body). Billed, so no refund.
        _fail(session, record, refund=False, reason="Claude call failed")
        return

    if result is None:
        # Declined keeps its count: the model produced billable tokens to say no.
        comprehension_store.mark_terminal(
            session, record.id, status=comprehension_store.STATUS_DECLINED
        )
        return

    comprehension_store.complete(
        session,
        record.id,
        cloud_translation=result.translation,
        grammar_notes=result.grammar_notes,
        context_notes=result.context_notes,
        tone_register=result.tone_register,
    )


def process_pending(
    *,
    page_path_for: Callable[..., Optional[Path]],
    limit: int = MAX_CONCURRENT_JOBS,
    session_factory: Callable[[], Session] = new_session,
) -> int:
    """Claim up to ``limit`` pending records, run them, and report how many ran.

    The whole of the worker's behaviour, callable synchronously so its tests
    need no threads and no sleeps -- the daemon thread below is a loop around
    this and nothing else.

    Each claimed record runs on its own session because SQLAlchemy sessions are
    not shared across threads. Claiming happens once, up front, on a session of
    its own: rows are marked ``running`` before any of them starts, so a second
    drain overlapping this one cannot pick the same work.
    """
    try:
        claim_session = session_factory()
    except RuntimeError:
        # Engine never initialised -- the app starts the worker even when
        # Postgres was down at boot, so this is reachable rather than defensive.
        logger.warning("Comprehension store unavailable; nothing claimed.")
        return 0
    try:
        record_ids = comprehension_store.claim_pending(claim_session, limit=limit)
    except SQLAlchemyError:
        claim_session.rollback()
        logger.warning("Could not claim comprehension records.", exc_info=True)
        return 0
    finally:
        claim_session.close()

    if not record_ids:
        return 0

    def run_one(record_id: int) -> None:
        session = session_factory()
        try:
            record = comprehension_store.get(session, record_id)
            if record is None:
                # Deleted between claim and run; nothing to do. The delete
                # endpoint only refunds a still-pending row, and this one was
                # already claimed, so the reservation stays spent.
                return
            run_record(session, record, page_path_for=page_path_for)
        except SQLAlchemyError:
            session.rollback()
            logger.warning(
                "Comprehension record %s: store failure while running.",
                record_id,
                exc_info=True,
            )
        except Exception:  # noqa: BLE001 -- see below; nothing may escape here
            # A record that escapes this stays `running` until the next restart,
            # holding its reservation and looking to every screen exactly like
            # work still in progress. Catching broadly is the lesser evil: one
            # record's unexpected failure must not strand it or abort the rest
            # of the batch.
            session.rollback()
            logger.warning(
                "Comprehension record %s: unexpected failure while running.",
                record_id,
                exc_info=True,
            )
        finally:
            session.close()

    with ThreadPoolExecutor(max_workers=limit) as pool:
        list(pool.map(run_one, record_ids))
    return len(record_ids)


class ComprehensionWorker:
    """The daemon thread that keeps calling ``process_pending``.

    Deliberately thin: it owns the loop, the sleep and the stop flag, and no
    decision worth a test. Anything that could be wrong lives in
    ``process_pending``.
    """

    def __init__(
        self,
        *,
        page_path_for: Callable[..., Optional[Path]],
        interval: float = POLL_INTERVAL_SECONDS,
    ) -> None:
        self._page_path_for = page_path_for
        self._interval = interval
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        """Release any orphaned claims, then begin draining in the background.

        The release runs before the loop starts and is correct because the API
        runs a single uvicorn worker: if this process has just started, nothing
        can still be executing, so every ``running`` row was orphaned by a
        restart. This is what makes a container restart mid-flight resume the
        work rather than strand it.
        """
        self._release_orphans()
        self._thread = threading.Thread(
            target=self._loop, name="comprehension-worker", daemon=True
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _release_orphans(self) -> None:
        try:
            session = new_session()
        except RuntimeError:
            logger.warning("Comprehension store unavailable; no orphans released.")
            return
        try:
            released = comprehension_store.release_orphaned_claims(session)
            if released:
                logger.info(
                    "Released %s orphaned comprehension record(s) back to pending.",
                    released,
                )
        except SQLAlchemyError:
            session.rollback()
            logger.warning("Could not release orphaned claims.", exc_info=True)
        finally:
            session.close()

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                ran = process_pending(page_path_for=self._page_path_for)
            except Exception:  # noqa: BLE001 -- the loop must outlive any one failure
                logger.warning("Comprehension drain failed.", exc_info=True)
                ran = 0
            # Only wait when there was nothing to do; a full batch means more
            # may be queued behind it.
            if ran == 0:
                self._stop.wait(self._interval)
