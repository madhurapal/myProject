"""
db_connector.py — DuckDB connection utility
Handles both local file-based DB and in-memory DB (for CI environments).

Usage:
    from connectors.db_connector import get_connection
    con = get_connection()
    df  = con.execute("SELECT * FROM dim_plans").df()
    con.close()
"""

import os
import duckdb
from pathlib import Path
from typing import Optional

# Default path: analytics.duckdb in project root
_DEFAULT_DB = Path(__file__).parent.parent / "analytics.duckdb"


def get_connection(db_path: Optional[str] = None, read_only: bool = False) -> duckdb.DuckDBPyConnection:
    """
    Return a DuckDB connection.

    Priority order for db_path:
      1. Explicit argument
      2. ANALYTICS_DB_PATH environment variable (used in GitHub Actions)
      3. Default: <project_root>/analytics.duckdb

    Args:
        db_path:   Path to .duckdb file. None = auto-detect.
        read_only: Open in read-only mode (safe for concurrent reads in CI).

    Returns:
        duckdb.DuckDBPyConnection
    """
    resolved = db_path or os.environ.get("ANALYTICS_DB_PATH") or str(_DEFAULT_DB)

    if not Path(resolved).exists() and not read_only:
        raise FileNotFoundError(
            f"Database not found at: {resolved}\n"
            f"Run `python database/seed.py` first to create and populate it."
        )

    con = duckdb.connect(resolved, read_only=read_only)
    _configure(con)
    return con


def _configure(con: duckdb.DuckDBPyConnection) -> None:
    """Apply session-level performance settings."""
    con.execute("SET threads TO 4")
    con.execute("SET memory_limit = '1GB'")
    # Enable progress bar for long queries (suppressed in CI)
    if os.environ.get("CI") != "true":
        con.execute("SET enable_progress_bar = true")


def table_row_counts(con: duckdb.DuckDBPyConnection) -> dict:
    """Return {table_name: row_count} for all fact and dim tables."""
    tables = con.execute("""
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'main'
        ORDER BY table_name
    """).fetchall()

    counts = {}
    for (tbl,) in tables:
        (n,) = con.execute(f"SELECT COUNT(*) FROM {tbl}").fetchone()
        counts[tbl] = n
    return counts


if __name__ == "__main__":
    con = get_connection()
    counts = table_row_counts(con)
    print("Table row counts:")
    for tbl, n in counts.items():
        print(f"  {tbl:<40} {n:>10,}")
    con.close()
