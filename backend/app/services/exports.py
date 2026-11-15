"""Project report exports (E03): CSV for spreadsheets, PDF for stakeholders.

Both formats share one row builder so the two downloads can never disagree.
Exports are read operations: any role with access to the project (including
viewers) may download them.
"""
import csv
import io
from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.errors import NotFoundError
from ..core.rules import require_project_access
from ..core.time import utc_now
from ..models import Assignee, Project, Task

CSV_MEDIA_TYPE = "text/csv"
PDF_MEDIA_TYPE = "application/pdf"

_HEADER = [
    "id",
    "title",
    "status",
    "priority",
    "due_date",
    "assignee",
    "created_at",
    "completed_at",
]


def _iso(value: datetime | date | None) -> str:
    """Compact UTC timestamp or plain date; empty when the column is NULL.

    `due_date` is a `date` while the other columns are `datetime`; only the
    datetime form accepts `sep`/`timespec`.
    """
    if not value:
        return ""
    if isinstance(value, datetime):
        return value.isoformat(sep=" ", timespec="seconds")
    return value.isoformat()


def _project_rows(
    db: Session, *, actor: Assignee, project_id: int
) -> tuple[Project, list[list[str]]]:
    """Load the project and its task rows (oldest first) for a report."""
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    require_project_access(actor.role, actor.project_id, project_id)
    tasks = list(
        db.scalars(
            select(Task).where(Task.project_id == project_id).order_by(Task.id)
        )
    )
    assignee_ids = {t.assignee_id for t in tasks if t.assignee_id is not None}
    names: dict[int, str] = {}
    if assignee_ids:
        names = {
            account.id: account.name
            for account in db.scalars(
                select(Assignee).where(Assignee.id.in_(assignee_ids))
            )
        }
    rows = [
        [
            str(task.id),
            task.title,
            task.status,
            task.priority,
            _iso(task.due_date),
            names.get(task.assignee_id, "Whole project"),
            _iso(task.created_at),
            _iso(task.completed_at),
        ]
        for task in tasks
    ]
    return project, rows


def csv_for(db: Session, *, actor: Assignee, project_id: int) -> bytes:
    """UTF-8 CSV with a header row; standard quoting for commas and quotes."""
    _, rows = _project_rows(db, actor=actor, project_id=project_id)
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(_HEADER)
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


def pdf_for(db: Session, *, actor: Assignee, project_id: int) -> bytes:
    """Single-document PDF: title, summary line, and one table of tasks."""
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.platypus import (
        Paragraph,
        SimpleDocTemplate,
        Spacer,
        Table,
        TableStyle,
    )

    project, rows = _project_rows(db, actor=actor, project_id=project_id)
    buffer = io.BytesIO()
    document = SimpleDocTemplate(
        buffer, pagesize=A4, title=f"{project.name} report"
    )
    styles = getSampleStyleSheet()
    generated = utc_now().isoformat(sep=" ", timespec="seconds")
    story = [
        Paragraph(f"Project report: {project.name}", styles["Title"]),
        Spacer(1, 8),
        Paragraph(
            f"{len(rows)} tasks &middot; generated {generated} UTC",
            styles["Normal"],
        ),
        Spacer(1, 12),
    ]
    if rows:
        # Plain strings do not wrap inside a reportlab table cell, so long
        # values are trimmed to keep every column readable.
        table_data = [["#", "Title", "Status", "Priority", "Due", "Assignee"]]
        table_data += [
            [
                row[0],
                row[1][:45],
                row[2],
                row[3],
                row[4][:10],
                row[5][:20],
            ]
            for row in rows
        ]
        table = Table(
            table_data,
            repeatRows=1,
            colWidths=[28, 210, 60, 55, 65, 90],
        )
        table.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#37474F")),
                    ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                    ("FONTSIZE", (0, 0), (-1, -1), 8),
                    ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#B0BEC5")),
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ]
            )
        )
        story.append(table)
    else:
        story.append(Paragraph("No tasks in this project yet.", styles["Normal"]))
    document.build(story)
    return buffer.getvalue()
