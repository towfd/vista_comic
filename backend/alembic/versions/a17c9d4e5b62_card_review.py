"""card_review, and the once-a-day guard on the ladder

Stage 4 of `.scratch/vocabulary-review/`.

`client_token` is unique so a resubmitted answer cannot count twice; a
duplicated wrong answer would drop a rung the reader never lost.

`last_ladder_move_on` is on the card rather than derived, because a review does
not know whether it was the one that moved the rung.

`local_date` is stored alongside `reviewed_at` because they answer different
questions: the timestamp is the server clock, and grouping a UTC+8 reader's day
by it would put everything before 08:00 on the previous day.

Revision ID: a17c9d4e5b62
Revises: c73f5b1de204
Create Date: 2026-08-20

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a17c9d4e5b62'
down_revision: Union[str, None] = 'c73f5b1de204'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'card_review',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('card_id', sa.Integer(), nullable=False),
        sa.Column('question_type', sa.String(), nullable=False),
        sa.Column('is_correct', sa.Boolean(), nullable=False),
        sa.Column('elapsed_ms', sa.Integer(), nullable=True),
        sa.Column('client_token', sa.String(), nullable=False),
        sa.Column('local_date', sa.Date(), nullable=False),
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['card_id'], ['learning_card.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('client_token', name='uq_card_review_client_token'),
    )
    op.add_column(
        'learning_card', sa.Column('last_ladder_move_on', sa.Date(), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('learning_card', 'last_ladder_move_on')
    op.drop_table('card_review')
