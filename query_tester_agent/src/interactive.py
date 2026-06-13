import sys

import questionary
from rich.console import Console

from .suggester import TestSuggestion

console = Console()


def approve_tests(suggestions: list[TestSuggestion]) -> list[TestSuggestion]:
    if not sys.stdin.isatty():
        console.print(
            "[yellow]Non-interactive terminal detected — all tests approved automatically.[/yellow]\n"
        )
        return suggestions

    choices = [_make_choice(i, s) for i, s in enumerate(suggestions, 1)]

    try:
        selected_names = questionary.checkbox(
            "Select tests to run  (↑↓ navigate · space toggle · enter confirm):",
            choices=choices,
        ).ask()
    except Exception:
        console.print(
            "[yellow]Could not launch interactive menu — all tests approved automatically.[/yellow]\n"
        )
        return suggestions

    if selected_names is None:  # Ctrl+C
        console.print("\n[bold red]Cancelled.[/bold red]")
        sys.exit(0)

    if not selected_names:
        console.print("[bold red]No tests selected. Nothing to run. Exiting.[/bold red]")
        sys.exit(0)

    approved = [s for s in suggestions if s.name in set(selected_names)]
    skipped = len(suggestions) - len(approved)
    console.print(
        f"\nRunning [bold green]{len(approved)}[/bold green] of {len(suggestions)} tests"
        + (f"  ({skipped} skipped)" if skipped else "")
        + "\n"
    )
    return approved


def _make_choice(index: int, s: TestSuggestion) -> questionary.Choice:
    col_label = s.column or "(table-level)"
    label = f"[{index:>2}]  {col_label:<20}  {s.test_type:<12}  {s.reason}"
    return questionary.Choice(title=label, value=s.name, checked=True)
