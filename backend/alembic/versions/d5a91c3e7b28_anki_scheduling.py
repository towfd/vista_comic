"""The Anki scheduling model: learning steps, seven slots, and a reset deck

Stage 6 ticket 01 of `.scratch/vocabulary-review/`.

Three changes, and the third is the one to read twice.

`learning_card` gains an explicit `state`, the learning step it is on, the slot
to return to after a lapse, and a `due_at` timestamp replacing `due_on` -- a
card due at 20:07 cannot be expressed as a day. `last_ladder_move_on` goes: it
was the remains of a once-a-day lock removed after the first acceptance pass.

`card_review` gains `context` (which mode asked) and `answered_at` (when the
reader actually answered, as opposed to when the answer reached the server --
they differ by hours once practice works offline). Existing rows are backfilled
as `review` answers whose `answered_at` is their `reviewed_at`, which is what
they were.

**Every card is reset to new.** This is deliberate and was confirmed with the
repo owner for the production database as well as this one. The old ladder could
barely climb before #86 -- a single wrong answer sealed a card for the day, so a
fresh deck never left the first rung -- and almost nothing had been earned. The
review rows are all kept: they are history, not state, and the log has been
complete since stage 1 so that adopting FSRS later stays an algorithm change.

That reset is also why `state` had to become a column. Afterwards, cards exist
with twenty answers on record and the state `new`, so "has reviews" stops being
a usable definition of "has been met".

Revision ID: d5a91c3e7b28
Revises: a17c9d4e5b62
Create Date: 2026-08-31

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'd5a91c3e7b28'
down_revision: Union[str, None] = 'a17c9d4e5b62'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('learning_card', sa.Column('state', sa.String(), nullable=True))
    op.add_column('learning_card', sa.Column('learning_step', sa.Integer(), nullable=True))
    op.add_column('learning_card', sa.Column('previous_stage', sa.Integer(), nullable=True))
    op.add_column(
        'learning_card',
        sa.Column('due_at', sa.DateTime(timezone=True), nullable=True),
    )

    # The reset. `due_at` is now rather than midnight of the old `due_on`,
    # because a new card waits on the day's quota rather than on a due date and
    # a past timestamp is the honest way to say "ready whenever you are".
    op.execute(
        """
        UPDATE learning_card
           SET state = 'new',
               learning_step = NULL,
               previous_stage = NULL,
               ladder_stage = 0,
               due_at = now()
        """
    )

    op.alter_column('learning_card', 'state', nullable=False)
    op.alter_column('learning_card', 'due_at', nullable=False)
    op.drop_column('learning_card', 'due_on')
    op.drop_column('learning_card', 'last_ladder_move_on')

    op.add_column('card_review', sa.Column('context', sa.String(), nullable=True))
    op.add_column(
        'card_review',
        sa.Column('answered_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.execute(
        """
        UPDATE card_review
           SET context = 'review',
               answered_at = reviewed_at
        """
    )
    op.alter_column('card_review', 'context', nullable=False)
    op.alter_column('card_review', 'answered_at', nullable=False)

    op.create_table(
        'study_settings',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column(
            'learning_steps', postgresql.ARRAY(sa.Integer()), nullable=False
        ),
        sa.Column('new_cards_per_day', sa.Integer(), nullable=False),
        sa.CheckConstraint('id = 1', name='ck_study_settings_single_row'),
        sa.PrimaryKeyConstraint('id'),
    )
    # The defaults, seeded here so the app never has to cope with a settings
    # table that exists and is empty.
    op.execute(
        """
        INSERT INTO study_settings (id, learning_steps, new_cards_per_day)
        VALUES (1, ARRAY[5, 7, 10], 15)
        """
    )


def downgrade() -> None:
    op.drop_table('study_settings')

    op.drop_column('card_review', 'answered_at')
    op.drop_column('card_review', 'context')

    op.add_column(
        'learning_card',
        sa.Column('last_ladder_move_on', sa.Date(), nullable=True),
    )
    op.add_column('learning_card', sa.Column('due_on', sa.Date(), nullable=True))
    # The reverse cannot restore what the upgrade reset; the best it can do is
    # give the old column a defensible value. A card is due on the day its
    # timestamp falls in.
    op.execute("UPDATE learning_card SET due_on = (due_at AT TIME ZONE 'UTC')::date")
    op.alter_column('learning_card', 'due_on', nullable=False)

    op.drop_column('learning_card', 'due_at')
    op.drop_column('learning_card', 'previous_stage')
    op.drop_column('learning_card', 'learning_step')
    op.drop_column('learning_card', 'state')
