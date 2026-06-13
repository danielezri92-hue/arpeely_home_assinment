from dataclasses import dataclass
from typing import Optional

import sqlglot
import sqlglot.expressions as exp


@dataclass
class OutputColumn:
    name: str
    source_table: Optional[str]
    raw_expr: str


@dataclass
class ParsedQuery:
    output_columns: list[OutputColumn]
    cte_names: list[str]
    has_join: bool
    nullable_side_aliases: set[str]   # table aliases on the right of LEFT JOINs
    source_sql: str


def parse_sql_file(path: str) -> ParsedQuery:
    with open(path) as f:
        sql = f.read()
    return parse_sql(sql)


def parse_sql(sql: str) -> ParsedQuery:
    statement = sqlglot.parse_one(sql)

    cte_names = [cte.alias for cte in statement.find_all(exp.CTE)]

    has_join = bool(statement.find(exp.Join))
    nullable_side_aliases = _get_nullable_side_aliases(statement)

    # The outermost SELECT's projection
    is_plain_select = isinstance(statement, exp.Select)
    select = statement if is_plain_select else statement.find(exp.Select)
    output_columns = [_extract_column(expr) for expr in select.expressions]

    # For CREATE TABLE / CREATE VIEW AS SELECT, embed only the SELECT in test CTEs.
    # DuckDB (and every warehouse) won't accept CREATE TABLE inside a WITH clause.
    source_sql = sql.strip() if is_plain_select else select.sql()

    return ParsedQuery(
        output_columns=output_columns,
        cte_names=cte_names,
        has_join=has_join,
        nullable_side_aliases=nullable_side_aliases,
        source_sql=source_sql,
    )


def _get_nullable_side_aliases(statement: exp.Expression) -> set[str]:
    aliases: set[str] = set()
    for join in statement.find_all(exp.Join):
        if join.side and join.side.upper() == "LEFT":
            alias = join.this.alias or (join.this.name if hasattr(join.this, "name") else None)
            if alias:
                aliases.add(alias.lower())
    return aliases


def _extract_column(expr: exp.Expression) -> OutputColumn:
    if isinstance(expr, exp.Alias):
        name = expr.alias
        inner = expr.this
        source_table = inner.table if isinstance(inner, exp.Column) else None
    elif isinstance(expr, exp.Column):
        name = expr.name
        source_table = expr.table or None
    elif isinstance(expr, exp.Star):
        name = "*"
        source_table = None
    else:
        name = expr.alias or expr.name or expr.sql()
        source_table = None

    return OutputColumn(name=name, source_table=source_table or None, raw_expr=expr.sql())
