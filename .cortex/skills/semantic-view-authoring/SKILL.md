---
name: semantic-view-authoring
description: >
  Author and review Snowflake Semantic Views as dbt models using the
  dbt_semantic_view package. Use when creating, editing, or reviewing a sv_*
  model in this project, or when a request mentions semantic view, metrics,
  dimensions, relationships, synonyms, or verified queries. Encodes the
  Snowflake CREATE SEMANTIC VIEW grammar, the package's materialization
  conventions, and this team's metadata standards.
tools:
  - read
  - write
  - edit
  - snowflake_sql_execute
---

# Instructions

Semantic Views are a recent Snowflake feature and the `dbt_semantic_view`
package is newer still - do not rely on memorized patterns from other tools
(LookML, dbt MetricFlow, Cube, etc.). Follow the rules below exactly.

A semantic view model is materialized as:

```
{{ config(materialized='semantic_view') }}
TABLES ( ... ) RELATIONSHIPS ( ... ) FACTS ( ... ) DIMENSIONS ( ... ) METRICS ( ... )
COMMENT = '...' AI_VERIFIED_QUERIES ( ... )
```

The package wraps the body in `CREATE OR REPLACE SEMANTIC VIEW <relation> <body>`.
You write everything after the relation name.

## Rules (in order)

1. **Clause order is mandatory:** `TABLES`, `RELATIONSHIPS`, `FACTS`,
   `DIMENSIONS`, `METRICS`, `COMMENT`, then `AI_VERIFIED_QUERIES`. Snowflake
   rejects out-of-order clauses (FACTS must precede DIMENSIONS, etc.).
2. **Reference dbt models, not raw tables.** Every logical table is
   `alias AS {{ ref('model_name') }}`. Never hard-code a database/schema.
3. **Declare keys and relationships.** Give each logical table a `PRIMARY KEY`,
   and declare every join in `RELATIONSHIPS` as
   `rel_name AS child (fk_col) REFERENCES parent (pk_col)`.
4. **Define the metric explicitly - do not assume column names imply meaning.**
   If multiple plausible measures exist (e.g. a header total vs. a line-derived
   net figure), the metric SQL must state which one is official, and the
   ambiguous column should carry a COMMENT saying it is NOT the metric.

## Team metadata standards (required)

- **Every** dimension and metric has `WITH SYNONYMS = (...)`.
- **Every** metric and any ambiguous fact has a `COMMENT` stating its exact
  business definition.
- The view has a top-level `COMMENT` describing its analytic purpose.
- Provide at least two `AI_VERIFIED_QUERIES`, with `ONBOARDING_QUESTION TRUE` on
  the best starter questions. Write their `SQL` against the semantic view using
  the **unqualified** view name (e.g. `FROM SEMANTIC_VIEW(sv_sales_analytics ...)`)
  so the same query is valid in DEV and PROD.
- Mark internal-only measures `PRIVATE`; everything queryable is `PUBLIC`.

## Validation workflow (always do this)

1. `dbt parse` to catch Jinja/ref errors.
2. Build the view: `dbt run --select <sv_model> --target dev`
3. Smoke-test a real question through the view:
   `SELECT * FROM SEMANTIC_VIEW(<db>.<schema>.<sv> METRICS <m> DIMENSIONS <d>);`
4. `DESCRIBE SEMANTIC VIEW <db>.<schema>.<sv>;` and confirm synonyms/comments
   persisted.

# PR Review checklist (developers and CI)

Verify each item and report pass/fail with file:line refs and a concrete fix for every failure:

1. Clause order: TABLES, RELATIONSHIPS, FACTS, DIMENSIONS, METRICS, COMMENT,
   AI_VERIFIED_QUERIES.
2. Every logical table has a PRIMARY KEY; every join is declared in RELATIONSHIPS.
3. Logical tables reference dbt models via `{{ ref(...) }}` (no hard-coded
   database/schema).
4. Every dimension and metric has `WITH SYNONYMS`.
5. Every metric (and any ambiguous fact) has a definition COMMENT; the view has a
   top-level COMMENT.
6. At least two AI_VERIFIED_QUERIES, written against the **unqualified** view name.
7. Internal-only measures marked PRIVATE.

Output: concise markdown titled by the model file, grouped into Pass / Fail, with
file:line references and a concrete fix for each failure. Do not modify any files.

# Best Practices

- One semantic view per analytic subject area; keep it small and curated.
- Prefer a clean star (fact + dimension) over stuffing many tables in one view.
- Name metrics for the business concept (`total_revenue`), not the SQL
  (`sum_net_rev`).
- Treat the verified queries as regression tests for the model's intent.

# Common Patterns

## Pattern 1: Disambiguating "revenue"

Define the metric explicitly and comment the trap column:

```
FACTS (
  orders.net_revenue AS orders.net_revenue
    COMMENT = 'Line-derived net revenue: extended_price * (1 - discount).',
  orders.order_total AS orders.order_total
    COMMENT = 'Header price; includes tax. NOT the official revenue metric.'
)
METRICS (
  orders.total_revenue AS SUM(orders.net_revenue)
    WITH SYNONYMS = ('revenue', 'net revenue', 'total sales')
    COMMENT = 'Official revenue: SUM of line-derived net revenue.'
)
```
