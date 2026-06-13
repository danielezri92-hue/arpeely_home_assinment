import os
from dataclasses import dataclass
from typing import Optional

import duckdb

from .suggester import TestSuggestion


@dataclass
class TestResult:
    name: str
    column: Optional[str]
    test_type: str
    reason: str
    failing_rows: Optional[int]   # None means the test SQL itself errored
    passed: bool
    error: Optional[str]


def run_tests(approved: list[TestSuggestion], data_dir: str = "sample_data") -> list[TestResult]:
    con = _connect(data_dir)
    results = [_run_one(con, t) for t in approved]
    con.close()
    return results


def _connect(data_dir: str) -> duckdb.DuckDBPyConnection:
    if not os.path.isdir(data_dir):
        raise FileNotFoundError(f"Sample data directory not found: {data_dir!r}")
    con = duckdb.connect()
    for fname in os.listdir(data_dir):
        if fname.endswith(".csv"):
            table = fname[:-4]
            path = os.path.abspath(os.path.join(data_dir, fname))
            con.execute(f"CREATE VIEW {table} AS SELECT * FROM read_csv_auto('{path}')")
    return con


def _run_one(con: duckdb.DuckDBPyConnection, test: TestSuggestion) -> TestResult:
    try:
        row = con.execute(test.sql).fetchone()
        failing_rows = int(row[0]) if row is not None else 0
        return TestResult(
            name=test.name,
            column=test.column,
            test_type=test.test_type,
            reason=test.reason,
            failing_rows=failing_rows,
            passed=failing_rows == 0,
            error=None,
        )
    except Exception as exc:
        return TestResult(
            name=test.name,
            column=test.column,
            test_type=test.test_type,
            reason=test.reason,
            failing_rows=None,
            passed=False,
            error=str(exc),
        )
