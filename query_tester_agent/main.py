import argparse
from rich.console import Console
from rich.table import Table
from rich.text import Text
from src.parser import parse_sql_file
from src.suggester import suggest_tests, TestSuggestion
from src.interactive import approve_tests
from src.runner import run_tests
from src.reporter import print_report
from src.exporter import save_tests

console = Console()

TYPE_STYLE = {
    "table_level": "bold magenta",
    "not_null":    "yellow",
    "unique":      "cyan",
    "format":      "green",
    "range":       "blue",
}


def main():
    parser = argparse.ArgumentParser(description="Data quality test generator")
    parser.add_argument("--sql",    required=True,         help="Path to SQL file")
    parser.add_argument("--data",   default="sample_data", help="Directory with sample CSV files")
    parser.add_argument("--output", default=None,          help="Path for generated test SQL file")
    args = parser.parse_args()

    default_output = args.sql.replace(".sql", "_tests.sql")
    output_path = args.output or default_output

    parsed = parse_sql_file(args.sql)

    console.print(f"\n[bold cyan]Query Analysis[/bold cyan]")
    console.print(f"  CTEs found   : {', '.join(parsed.cte_names) if parsed.cte_names else 'none'}")
    console.print(f"  Contains join: {'yes' if parsed.has_join else 'no'}")
    console.print(f"  Output cols  : {len(parsed.output_columns)}\n")

    suggestions = suggest_tests(parsed)
    _print_suggestions(suggestions)

    approved = approve_tests(suggestions)

    console.print("[bold cyan]Running tests...[/bold cyan]\n")
    results = run_tests(approved, data_dir=args.data)
    print_report(results)

    save_tests(approved, results, source_sql_path=args.sql, output_path=output_path, data_dir=args.data)
    console.print(f"[dim]Test SQL saved to:[/dim] [bold]{output_path}[/bold]\n")


def _print_suggestions(suggestions: list[TestSuggestion]) -> None:
    table = Table(title=f"Suggested Tests  ({len(suggestions)} total)", show_lines=True)
    table.add_column("#",          style="dim",  width=4)
    table.add_column("Column",     style="bold", min_width=18)
    table.add_column("Type",       min_width=12)
    table.add_column("Reason")

    for i, s in enumerate(suggestions, 1):
        style = TYPE_STYLE.get(s.test_type, "")
        table.add_row(
            str(i),
            s.column or "[dim](table-level)[/dim]",
            Text(s.test_type, style=style),
            s.reason,
        )

    console.print(table)


if __name__ == "__main__":
    main()
