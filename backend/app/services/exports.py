"""Project report downloads: CSV and a minimal one-page PDF."""
import csv
import io
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.errors import NotFoundError, RuleError
from ..core.rules import is_admin
from ..models import Assignee, Project, Task

EXPORT_FORMATS = ("csv", "pdf")

_CSV_HEADER = (
    "id",
    "title",
    "status",
    "priority",
    "assignee_id",
    "due_date",
    "created_at",
    "completed_at",
)


def build_export(
    db: Session, *, actor: Assignee, project_id: int, format: str
) -> tuple[bytes, str, str]:
    """Return `(bytes, media type, filename)` for the requested report."""
    if format not in EXPORT_FORMATS:
        raise RuleError("Format must be 'csv' or 'pdf'.")
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    if not is_admin(actor.role) and actor.project_id != project_id:
        raise RuleError("You can only export your own project.")
    tasks = list(
        db.scalars(
            select(Task)
            .where(Task.project_id == project_id)
            .order_by(Task.created_at.asc(), Task.id.asc())
        ).all()
    )
    if format == "csv":
        return (
            _csv_bytes(tasks),
            "text/csv; charset=utf-8",
            f"project-{project_id}-report.csv",
        )
    return (
        _pdf_bytes(project.name, tasks),
        "application/pdf",
        f"project-{project_id}-report.pdf",
    )


def _row(task: Task) -> list[str]:
    return [
        str(task.id),
        task.title,
        task.status,
        task.priority,
        "" if task.assignee_id is None else str(task.assignee_id),
        _iso(task.due_date),
        task.created_at.isoformat(timespec="seconds"),
        "" if task.completed_at is None else task.completed_at.isoformat(timespec="seconds"),
    ]


def _iso(value: date | None) -> str:
    return "" if value is None else value.isoformat()


def _csv_bytes(tasks: list[Task]) -> bytes:
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(_CSV_HEADER)
    for task in tasks:
        writer.writerow(_row(task))
    return buffer.getvalue().encode("utf-8")


def _pdf_text(value: str) -> str:
    """Escape a PDF literal string; non-Latin-1 glyphs become '?'."""
    safe = value.encode("latin-1", "replace").decode("latin-1")
    return safe.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def _pdf_bytes(project_name: str, tasks: list[Task]) -> bytes:
    """Build a small valid one-page PDF without extra dependencies."""
    lines = [f"Task report - {project_name}", f"Tasks: {len(tasks)}", ""]
    lines.append("ID | Title | Status | Priority | Assignee | Due | Created")
    for task in tasks[:45]:
        row = _row(task)
        lines.append(
            f"{row[0]} | {_truncate(row[1], 42)} | {row[2]} | {row[3]} | "
            f"{row[4] or '-'} | {row[5] or '-'} | {row[6][:16]}"
        )
    if len(tasks) > 45:
        lines.append(f"... and {len(tasks) - 45} more tasks")

    content = "BT /F1 10 Tf 48 800 Td 14 TL\n"
    for line in lines:
        content += f"({_pdf_text(line)}) Tj T*\n"
    content += "ET"
    stream = content.encode("latin-1", "replace")

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 842] "
            b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
        ),
        (
            f"<< /Length {len(stream)} >>\nstream\n".encode("ascii")
            + stream
            + b"\nendstream"
        ),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]

    out = bytearray(b"%PDF-1.4\n")
    offsets: list[int] = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n".encode("ascii") + body + b"\nendobj\n"
    xref_offset = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode("ascii")
    out += b"0000000000 65535 f \n"
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode("ascii")
    out += (
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref_offset}\n%%EOF\n"
    ).encode("ascii")
    return bytes(out)


def _truncate(value: str, limit: int) -> str:
    return value if len(value) <= limit else value[: limit - 1] + "…"
