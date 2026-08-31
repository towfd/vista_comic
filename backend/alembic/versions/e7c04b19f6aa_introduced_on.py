"""learning_card.introduced_on: the day a card stopped being new

Stage 6 ticket 03 of `.scratch/vocabulary-review/`.

The daily new-card quota counts cards met for the first time today, and nothing
recorded that. Deriving it from the review log looked possible and is not: the
stage 6 migration resets cards while keeping their rows, so a card's oldest
answer is not when it was met — a reset card would be introduced for free.

The reader's day, not the server's, for the reason `card_review.local_date`
gives: on UTC+8 a UTC boundary moves the line to eight in the morning.

Nullable, and NULL for every existing row, which is correct rather than merely
convenient: the previous migration reset every card to new, and a new card has
not been introduced.

Revision ID: e7c04b19f6aa
Revises: d5a91c3e7b28
Create Date: 2026-08-31

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e7c04b19f6aa'
down_revision: Union[str, None] = 'd5a91c3e7b28'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'learning_card', sa.Column('introduced_on', sa.Date(), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('learning_card', 'introduced_on')
