# PostgreSQL Table Quarantine & Safe Cleanup

## Overview

This project demonstrates a safe, reversible workflow for identifying and removing unused PostgreSQL tables without immediately risking broken reports, ETL jobs, or scripts.

It is based on a real production-inspired data maintenance task. All company-specific names, infrastructure details, and sensitive identifiers have been anonymized.

## Business Problem

A PostgreSQL staging environment had accumulated many historical copies, test tables, snapshots, and one-off datasets. Some tables were large, but it was unclear which ones were still used by BI reports, scheduled scripts, views, or other processes.

Deleting tables immediately with `DROP TABLE` would be risky because usage statistics can be incomplete and some dependencies may only run weekly or monthly.

## Solution: Quarantine Before DROP

Instead of deleting a table immediately, the workflow moves it into a dedicated `zz_quarantine` schema for a defined observation period.

```text
Candidate table
     |
     v
Usage & dependency checks
     |
     v
zz_quarantine
     |
     +---- issue detected ----> RESTORE
     |
     +---- no issue ----------> DROP
```

The key idea is a controlled **scream test**: applications that reference a table by its old schema-qualified name will fail and reveal that the table is still needed. Because the table is only moved, not deleted, it can be restored quickly.

## Decision Framework

Before a table enters quarantine, four questions are checked:

1. Is anyone reading it?
2. Is anything writing to it?
3. Does it contain unique data?
4. Can it be rebuilt from an upstream source?

A candidate is quarantined only when the evidence supports that it is safe to test.

## PostgreSQL Checks Used

### Read/write activity

```sql
SELECT
    s.schemaname,
    s.relname,
    c.reltuples::bigint AS rows_estimate,
    pg_size_pretty(pg_total_relation_size(s.relid)) AS size,
    s.seq_scan + COALESCE(s.idx_scan, 0) AS reads,
    s.n_tup_ins + s.n_tup_upd + s.n_tup_del AS writes
FROM pg_stat_user_tables s
JOIN pg_class c ON c.oid = s.relid
ORDER BY pg_total_relation_size(s.relid) DESC;
```

### Statistics reset date

```sql
SELECT stats_reset
FROM pg_stat_database
WHERE datname = current_database();
```

This matters because `reads = 0` only proves that no reads were recorded **since the last statistics reset**.

### View dependencies

```sql
SELECT view_schema, view_name
FROM information_schema.view_table_usage
WHERE table_schema = 'source_schema'
  AND table_name = 'table_name';
```

Views require a separate dependency check because PostgreSQL may keep them working after a table is moved to another schema.

## Quarantine Design

The workflow creates:

- `zz_quarantine` — temporary holding schema;
- `control.quarantine_log` — audit log;
- a defined observation period before deletion;
- explicit `RESTORED` / `DROPPED` statuses;
- a no-`CASCADE` deletion rule as an additional safeguard.

## Example Lifecycle

```sql
ALTER TABLE source_schema.table_name
SET SCHEMA zz_quarantine;
```

The move changes metadata rather than copying the table data.

If a dependency is discovered:

```sql
ALTER TABLE zz_quarantine.table_name
SET SCHEMA source_schema;
```

If the observation period passes without issues:

```sql
DROP TABLE zz_quarantine.table_name;
```

## Safety Controls

- Never use `DROP ... CASCADE` in the quarantine workflow.
- Check views separately.
- Consider weekly/monthly reporting cycles before selecting the quarantine period.
- Avoid moving tables while BI refreshes or heavy queries are running because `ALTER TABLE` requires a strong lock.
- Verify recoverability before deletion.
- For important datasets, create a backup/dump before final `DROP`.

## Repository Structure

```text
postgresql-table-quarantine/
├── README.md
├── sql/
│   ├── 01_create_quarantine.sql
│   ├── 02_candidate_checks.sql
│   ├── 03_quarantine_table.sql
│   └── 04_restore_or_drop.sql
└── marketplace/
    ├── upwork-portfolio.md
    └── fiverr-gig.md
```

## Skills Demonstrated

- PostgreSQL administration and SQL
- Data lifecycle management
- Dependency analysis
- Safe production changes
- BI / ETL impact analysis
- Audit logging
- Rollback planning
- Risk-aware data engineering

## Why This Matters

The project shows more than writing SQL. It demonstrates how to make a production change safely: gather evidence, design rollback, document the decision, monitor the result, and only then perform irreversible cleanup.

## Author

Anna Klymchuk  
Power BI / SQL / Data Engineering
