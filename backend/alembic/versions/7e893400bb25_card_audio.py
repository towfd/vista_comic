"""card_audio: one Vietnamese recording per card, written from outside this repo

Ticket 01 of `.scratch/card-audio/`.

The Text-To-Speech repo's writer fills this table through its own `card_tts`
role; this repo owns the table and only reads it. One row per card, so
`card_id` is the primary key, and a deleted card takes its recording with it.

`source_text` is the card's text at the moment the recording was made. A card
whose text has been corrected since is treated as having no audio until the
writer runs again; nothing here deletes the stale row.

The `GRANT SELECT, INSERT, UPDATE ON card_audio TO card_tts` from the spec
("The writer's role") is lost when the table is dropped: after a downgrade and
upgrade, or anything else that recreates it, run that `GRANT` again.

Revision ID: 7e893400bb25
Revises: b6e2f0c4a913
Create Date: 2026-11-18

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7e893400bb25'
down_revision: Union[str, None] = 'b6e2f0c4a913'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'card_audio',
        sa.Column('card_id', sa.Integer(), nullable=False),
        sa.Column('source_text', sa.String(), nullable=False),
        sa.Column('voice', sa.String(), nullable=False),
        sa.Column('mime_type', sa.String(), nullable=False),
        sa.Column('audio', sa.LargeBinary(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['card_id'], ['learning_card.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('card_id'),
    )


def downgrade() -> None:
    op.drop_table('card_audio')
