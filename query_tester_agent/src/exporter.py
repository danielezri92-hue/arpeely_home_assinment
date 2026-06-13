import os
from datetime import datetime

from .runner import TestResult
from .suggester import TestSuggestion


def save_tests(
    approved: list[TestSuggestion],
    results: list[TestResult],
    source_sql_path: str,
    output_path: str,
    data_dir: str = "sample_data",
) -> None:
    result_map = {r.name: r for r in results}

    lines: list[str] = []

    # ── local-only preamble ───────────────────────────────────────────────────
    lines += [
        "-- ================================================================",
        "-- LOCAL SETUP — DuckDB / sample data only",
        "-- Creates one view per CSV so the tests below can run locally.",
        "-- On a real warehouse: delete this block. The tests reference",
        "-- your actual table names directly — nothing else to change.",
        "-- ================================================================",
        "",
    ]
    for fname in sorted(os.listdir(data_dir)):
        if fname.endswith(".csv"):
            view_name = fname[:-4]
            abs_path  = os.path.abspath(os.path.join(data_dir, fname))
            lines += [
                f"CREATE OR REPLACE VIEW {view_name} AS",
                f"    SELECT * FROM read_csv_auto('{abs_path}');",
                "",
            ]

    # ── test blocks ───────────────────────────────────────────────────────────
    lines += [
        "-- ================================================================",
        "-- Data quality tests",
        f"-- Source  : {source_sql_path}",
        f"-- Created : {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"-- Tests   : {len(approved)}",
        "-- ================================================================",
        "",
    ]

    for i, test in enumerate(approved, 1):
        col_label = test.column or "(table-level)"
        result    = result_map.get(test.name)

        lines.append(f"-- [{i:>2}] {test.name}")
        lines.append(f"--      column : {col_label}")
        lines.append(f"--      type   : {test.test_type}")
        lines.extend(_wrap_comment("reason", test.reason))
        if result is not None:
            status = "PASS" if result.passed else f"FAIL — {result.failing_rows} failing row(s)"
            lines.append(f"--      last run: {status}")
        lines.append(test.sql + ";")
        lines.append("")

    with open(output_path, "w") as f:
        f.write("\n".join(lines))


def _wrap_comment(label: str, text: str, width: int = 72) -> list[str]:
    prefix_first = f"--      {label} : "
    prefix_cont  = "--      " + " " * (len(label) + 3)
    words = text.split()
    lines, current = [], ""
    for word in words:
        candidate = (current + " " + word).strip()
        limit = width - len(prefix_first if not lines else prefix_cont)
        if len(candidate) > limit and current:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    result = [prefix_first + lines[0]] if lines else [prefix_first]
    for line in lines[1:]:
        result.append(prefix_cont + line)
    return result
