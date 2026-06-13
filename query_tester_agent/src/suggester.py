import re
from dataclasses import dataclass
from typing import Optional

from .parser import OutputColumn, ParsedQuery


@dataclass
class TestSuggestion:
    name: str           # machine-readable slug, e.g. user_id__unique
    column: Optional[str]   # None for table-level tests
    test_type: str      # not_null | unique | format | range | table_level
    reason: str         # shown to user + saved as SQL comment
    sql: str            # returns failing_rows; 0 = pass


def suggest_tests(parsed: ParsedQuery) -> list[TestSuggestion]:
    suggestions: list[TestSuggestion] = []
    suggestions.extend(_table_level_tests(parsed))
    for col in parsed.output_columns:
        suggestions.extend(_column_tests(col, parsed))
    return suggestions


# ── SQL helpers ───────────────────────────────────────────────────────────────

def _wrap(source_sql: str, test_select: str) -> str:
    indented = "\n".join("    " + line for line in source_sql.splitlines())
    return f"WITH _source AS (\n{indented}\n)\n{test_select}"


def _where_count(source_sql: str, condition: str) -> str:
    return _wrap(source_sql, f"SELECT COUNT(*) AS failing_rows\nFROM _source\nWHERE {condition}")


# ── table-level tests ─────────────────────────────────────────────────────────

def _table_level_tests(parsed: ParsedQuery) -> list[TestSuggestion]:
    col_list = ", ".join(c.name for c in parsed.output_columns)
    return [
        TestSuggestion(
            name="table__row_count_positive",
            column=None,
            test_type="table_level",
            reason="Result set should not be empty; zero rows usually means a broken filter or missing upstream data",
            sql=_wrap(
                parsed.source_sql,
                "SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END AS failing_rows\nFROM _source",
            ),
        ),
        TestSuggestion(
            name="table__no_duplicate_rows",
            column=None,
            test_type="table_level",
            reason="Full-row duplicates indicate a join fanout or a missing deduplication step upstream",
            sql=_wrap(
                parsed.source_sql,
                f"SELECT COUNT(*) AS failing_rows FROM (\n"
                f"    SELECT {col_list}, COUNT(*) AS _cnt\n"
                f"    FROM _source\n"
                f"    GROUP BY {col_list}\n"
                f"    HAVING _cnt > 1\n"
                f")",
            ),
        ),
    ]


# ── per-column tests ──────────────────────────────────────────────────────────

def _column_tests(col: OutputColumn, parsed: ParsedQuery) -> list[TestSuggestion]:
    tests: list[TestSuggestion] = []
    source_sql = parsed.source_sql
    n = col.name.lower()
    coalesced = _is_coalesce_wrapped(col.raw_expr)

    # NOT NULL — skip columns already protected by COALESCE
    not_null_reason = _not_null_reason(col.name, n)
    if not coalesced and not_null_reason:
        on_nullable_side = (
            col.source_table is not None
            and col.source_table.lower() in parsed.nullable_side_aliases
        )
        if on_nullable_side:
            not_null_reason += " — comes from the nullable side of a LEFT JOIN, NULLs may be expected here"
        tests.append(TestSuggestion(
            name=f"{col.name}__not_null",
            column=col.name,
            test_type="not_null",
            reason=not_null_reason,
            sql=_where_count(source_sql, f"{col.name} IS NULL"),
        ))

    # UNIQUE — columns whose name is or ends in _id
    if re.search(r"(^|_)id$", n):
        tests.append(TestSuggestion(
            name=f"{col.name}__unique",
            column=col.name,
            test_type="unique",
            reason=f"Column name ends in '_id' — expected to be a unique identifier per output row",
            sql=_wrap(
                source_sql,
                f"SELECT COUNT({col.name}) - COUNT(DISTINCT {col.name}) AS failing_rows\nFROM _source",
            ),
        ))

    # EMAIL format
    if "email" in n:
        tests.append(TestSuggestion(
            name=f"{col.name}__email_format",
            column=col.name,
            test_type="format",
            reason=f"'{col.name}' looks like an email column; values should contain '@' and a domain",
            sql=_where_count(
                source_sql,
                f"{col.name} IS NOT NULL AND {col.name} NOT LIKE '%@%.%'",
            ),
        ))

    # COUNTRY CODE — 2-letter ISO 3166
    if re.search(r"country_?code$|^country$", n):
        tests.append(TestSuggestion(
            name=f"{col.name}__country_code_length",
            column=col.name,
            test_type="format",
            reason=f"'{col.name}' looks like an ISO 3166 country code; valid values are exactly 2 characters",
            sql=_where_count(
                source_sql,
                f"{col.name} IS NOT NULL AND LENGTH({col.name}) <> 2",
            ),
        ))

    # NON-NEGATIVE — counts, amounts, and durations
    if re.search(r"^(total|num|count)_|_(count|orders|amount|spent|days|tenure|revenue|price)$", n):
        tests.append(TestSuggestion(
            name=f"{col.name}__non_negative",
            column=col.name,
            test_type="range",
            reason=f"'{col.name}' is a count/amount/duration and should never be negative",
            sql=_where_count(source_sql, f"{col.name} < 0"),
        ))

    return tests


# ── heuristics ────────────────────────────────────────────────────────────────

def _not_null_reason(col_name: str, name_lower: str) -> Optional[str]:
    """Return a pattern-specific NOT NULL reason, or None if no pattern matches."""
    if re.search(r"(^|_)id$", name_lower):
        return f"'{col_name}' is an identifier column — a NULL here means the row is unidentifiable"
    if "email" in name_lower:
        return f"'{col_name}' is an email field — usually required for user identification and communication"
    if re.search(r"country_?code$|^country$", name_lower):
        return f"'{col_name}' is a categorical field — a missing country code usually signals bad or incomplete data"
    if re.search(r"_at$", name_lower):
        return f"'{col_name}' is a timestamp — every record should have a populated event time"
    if re.search(r"_date$", name_lower):
        return f"'{col_name}' is a date field — NULL dates make time-based analysis unreliable"
    return None


def _is_coalesce_wrapped(raw_expr: str) -> bool:
    return raw_expr.strip().upper().startswith("COALESCE")
