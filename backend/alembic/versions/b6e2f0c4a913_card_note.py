"""learning_card.note: the reader's own explanation of a card

Ticket 01 of `.scratch/card-notes/`.

Plain text the reader writes while collecting or later in the card library,
shown after an answer. Nullable, and NULL for every existing row: no card had a
note before, and none is ever generated.

Revision ID: b6e2f0c4a913
Revises: f3b8d21a9c47
Create Date: 2026-11-04

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b6e2f0c4a913'
down_revision: Union[str, None] = 'f3b8d21a9c47'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('learning_card', sa.Column('note', sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column('learning_card', 'note')
