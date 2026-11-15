"""Operational maintenance commands.

Run inside the API container, for example:

    docker compose exec -T api python -m app.maintenance purge-events
"""
import argparse
from collections.abc import Sequence

from .core.config import ANALYTICS_RETENTION_DAYS
from .core.database import SessionLocal
from .services.analytics_service import purge_old_events


def main(argv: Sequence[str] | None = None) -> int:
    """Entry point for the documented maintenance commands."""
    parser = argparse.ArgumentParser(prog="python -m app.maintenance")
    commands = parser.add_subparsers(dest="command", required=True)
    purge = commands.add_parser(
        "purge-events",
        help="Delete analytics events older than the retention window.",
    )
    purge.add_argument(
        "--days",
        type=int,
        default=ANALYTICS_RETENTION_DAYS,
        help="Retention window in days (default: ANALYTICS_RETENTION_DAYS).",
    )
    args = parser.parse_args(argv)
    if args.days <= 0:
        parser.error("--days must be positive")

    with SessionLocal() as db:
        deleted = purge_old_events(db, days=args.days)
    print(f"Deleted {deleted} analytics event(s) older than {args.days} days.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
