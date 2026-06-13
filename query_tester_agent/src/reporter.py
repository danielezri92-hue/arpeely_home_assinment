from rich.console import Console
from rich.table import Table
from rich.text import Text

from .runner import TestResult

console = Console()


def print_report(results: list[TestResult]) -> None:
    table = Table(title="Test Results", show_lines=True)
    table.add_column("#",            style="dim", width=4)
    table.add_column("Column",       min_width=18)
    table.add_column("Type",         min_width=12)
    table.add_column("Status",       min_width=8)
    table.add_column("Failing rows", justify="right")

    for i, r in enumerate(results, 1):
        col_label = r.column or "(table-level)"
        if r.error:
            status       = Text("ERROR",  style="bold yellow")
            failing_cell = Text(r.error[:50], style="dim yellow")
        elif r.passed:
            status       = Text("✓ PASS", style="bold green")
            failing_cell = Text("0",      style="dim")
        else:
            status       = Text("✗ FAIL", style="bold red")
            failing_cell = Text(str(r.failing_rows), style="bold red")

        table.add_row(str(i), col_label, r.test_type, status, failing_cell)

    console.print(table)
    _print_summary(results)


def _print_summary(results: list[TestResult]) -> None:
    passed = sum(1 for r in results if r.passed)
    failed = sum(1 for r in results if not r.passed and not r.error)
    errors = sum(1 for r in results if r.error)

    parts = [f"[bold green]{passed} passed[/bold green]"]
    if failed:
        parts.append(f"[bold red]{failed} failed[/bold red]")
    if errors:
        parts.append(f"[bold yellow]{errors} error{'s' if errors > 1 else ''}[/bold yellow]")

    console.print("  " + "  ·  ".join(parts) + "\n")
