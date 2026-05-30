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

# When to Use

Invoke this skill whenever you:

- Create a new `models/marts/sv_*.sql` semantic view model.
- Edit metrics, dimensions, facts, relationships, synonyms, or verified queries
  in an existing semantic view.
- Review a pull request that touches a semantic view model.

Semantic Views are a recent Snowflake feature and the `dbt_semantic_view`
package is newer still - do not rely on memorized patterns from other tools
(LookML, dbt MetricFlow, Cube, etc.). Follow the rules below exactly.

# What This Skill Provides

- The correct `CREATE SEMANTIC VIEW` body that the `dbt_semantic_view`
  materialization expects (the model file IS the body of the DDL).
- This team's metadata standards that make a semantic view genuinely useful to
  an AI agent (the whole reason the layer exists).
- A validation workflow that proves the view builds and answers questions.

# Instructions

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
   `alias AS {{ ref('model_name') }}` so lineage and env (DEV/PROD) resolve
   correctly. Never hard-code a database/schema.
3. **Declare keys and relationships.** Give each logical table a `PRIMARY KEY`,
   and declare every join in `RELATIONSHIPS` as
   `rel_name AS child (fk_col) REFERENCES parent (pk_col)`. This is what stops an
   agent from inventing wrong joins or fanning out a measure.
4. **Define the metric explicitly - do not assume column names imply meaning.**
   If multiple plausible measures exist (e.g. a header total vs. a line-derived
   net figure), the metric SQL must state which one is official, and the
   ambiguous column should carry a COMMENT saying it is NOT the metric.

## Team metadata standards (required)

- **Every** dimension and metric has `WITH SYNONYMS = (...)` covering the
  business phrasings a user would actually type (e.g. `'AOV'`,
  `'average basket size'`).
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
2. Build only the view locally - fast, no deploy round-trip
   (assumes local `~/.dbt` auth is set up and `dbt deps` has been run):
   `dbt run --select <sv_model> --target dev`
   This calls dbt directly for development; production still goes through
   `snow dbt deploy` + `snow dbt execute` (see AGENTS.md "How to run").
3. Smoke-test a real question through the view:
   `SELECT * FROM SEMANTIC_VIEW(<db>.<schema>.<sv> METRICS <m> DIMENSIONS <d>);`
4. `DESCRIBE SEMANTIC VIEW <db>.<schema>.<sv>;` and confirm synonyms/comments
   persisted.

# PR Review checklist (developers and CI)

This is the single source of truth for reviewing a semantic view change - used
both by developers ("review @sv_x using semantic-view-authoring") and by the CI
review workflow. Verify each item and report pass/fail with file:line references
and a concrete fix for every failure:

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

A mart exposes both `order_total` (header, includes tax) and `net_revenue`
(line-derived). Define the metric explicitly and comment the trap column:

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

## Pattern 2: A verified query that is DEV/PROD-portable

```
AI_VERIFIED_QUERIES (
  revenue_by_segment AS (
    QUESTION 'What is total net revenue by market segment?'
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT * FROM SEMANTIC_VIEW(sv_sales_analytics METRICS total_revenue DIMENSIONS market_segment)'
  )
)
```

# Examples

## Example 1: Create a new semantic view

User: Use semantic-view-authoring to create a sales semantic view over
mart_order_sales and stg_customers.

Assistant: Authors `models/marts/sv_sales_analytics.sql` with TABLES (PK +
synonyms), a RELATIONSHIPS join, FACTS, DIMENSIONS and METRICS (every one with
synonyms/comments), a top-level COMMENT, and two AI_VERIFIED_QUERIES; then runs
the validation workflow and reports the smoke-test result.

## Example 2: Review a semantic view change

User: Review @models/marts/sv_sales_analytics.sql using semantic-view-authoring.

Assistant: Checks clause order; that every table has a PRIMARY KEY and every join
a RELATIONSHIP; that each metric/dimension has synonyms and each metric a
definition COMMENT; that ambiguous facts are commented; that verified queries
exist and use the unqualified view name. Reports concrete, line-referenced fixes.
