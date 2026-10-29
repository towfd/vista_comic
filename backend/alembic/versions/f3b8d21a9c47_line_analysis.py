"""line_analysis: the web reader's word-by-word breakdown of a bubble line

Ticket 01 of `.scratch/web-line-analysis/`. One row per (line, reviewed
translation, model), which is both the stored analysis and the queue the worker
drains. See `app/db.LineAnalysis`.

Revision ID: f3b8d21a9c47
Revises: e7c04b19f6aa
Create Date: 2026-10-29

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'f3b8d21a9c47'
down_revision: Union[str, None] = 'e7c04b19f6aa'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'line_analysis',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('source_text', sa.String(), nullable=False),
        sa.Column('source_key', sa.String(), nullable=False),
        sa.Column('translation', sa.String(), nullable=False),
        sa.Column('model', sa.String(), nullable=False),
        sa.Column('names', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('status', sa.String(), nullable=False),
        sa.Column('failure', sa.String(), nullable=True),
        sa.Column('result', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column('usage_date', sa.Date(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint(
            'source_key', 'translation', 'model', name='uq_line_analysis_identity'
        ),
    )


def downgrade() -> None:
    op.drop_table('line_analysis')
