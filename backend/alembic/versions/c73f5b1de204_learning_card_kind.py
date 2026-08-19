"""learning_card.kind: the reader says whether it is a word or a sentence

Stage 1 ticket 06 of `.scratch/vocabulary-review/`.

Nullable on purpose. Cards collected before this column existed have no answer,
and inventing one would be the guess the two save buttons exist to replace.

Revision ID: c73f5b1de204
Revises: 9c41a7be03d5
Create Date: 2026-08-19

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c73f5b1de204'
down_revision: Union[str, None] = '9c41a7be03d5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('learning_card', sa.Column('kind', sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column('learning_card', 'kind')
