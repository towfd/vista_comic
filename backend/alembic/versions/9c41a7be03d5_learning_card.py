"""learning_card: the deck the vocabulary review system is built on

Stage 1 of `.scratch/vocabulary-review/prd.md`. One row per line the reader
pressed add on.

The unique constraint is the interesting part: `(normalized_key,
target_language)` is the card's identity, and the comic is deliberately not in
it. See `app/normalization.py` for the rule that produces the key, and
`app/db.LearningCard` for why the identity is global.

Revision ID: 9c41a7be03d5
Revises: 4085885413a9
Create Date: 2026-08-19

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '9c41a7be03d5'
down_revision: Union[str, None] = '4085885413a9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'learning_card',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('source_text', sa.String(), nullable=False),
        sa.Column('normalized_key', sa.String(), nullable=False),
        sa.Column('translation', sa.String(), nullable=False),
        sa.Column('target_language', sa.String(), nullable=False),
        sa.Column('comic_id', sa.String(), nullable=False),
        sa.Column('chapter_id', sa.String(), nullable=False),
        sa.Column('page_number', sa.Integer(), nullable=False),
        sa.Column('comprehension_record_id', sa.Integer(), nullable=True),
        sa.Column('ladder_stage', sa.Integer(), nullable=False),
        sa.Column('due_on', sa.Date(), nullable=False),
        sa.Column('lookup_count', sa.Integer(), nullable=False),
        sa.Column('last_looked_up_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('archived_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ['comprehension_record_id'],
            ['comprehension_record.id'],
            ondelete='SET NULL',
        ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint(
            'normalized_key', 'target_language', name='uq_learning_card_identity'
        ),
    )


def downgrade() -> None:
    op.drop_table('learning_card')
