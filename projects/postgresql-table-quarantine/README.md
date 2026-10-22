# PostgreSQL Database Audit, Lineage & Safe Cleanup

## Overview

This project demonstrates a production-minded workflow for auditing an entire PostgreSQL analytics database, identifying active and inactive tables, mapping dependencies, detecting duplicate candidates, selecting canonical datasets, migrating consumers to current tables, and safely retiring obsolete objects through a controlled quarantine process.

It is based on a real production-inspired data maintenance task. All company-specific names, infrastructure details, and sensitive identifiers are anonymized.

## Business Problem

A PostgreSQL staging environment had accumulated historical copies, test tables, snapshots, one-off datasets, and large duplicate-like tables. It was unclear:

- which tables were still actively read or written;
- which tables were no longer used;
- which tables were oversized or suspicious;
- which datasets were duplicate or superseded versions;
- which views, BI reports, scripts, or scheduled processes depended on each table;
- which table should be treated as the current canonical source;
- whether consumers had already migrated to the latest version;
- which old tables could be retired safely.

Deleting objects immediately with `DROP TABLE` would be risky because usage statistics may be incomplete, some consumers run only weekly or monthly, and some dependencies are outside PostgreSQL itself.

## Target Architecture

```text
FULL DATABASE AUDIT
        |
        v
Inventory: tables / rows / size / reads / writes
        |
        v
Classify: active / inactive / suspicious / oversized
        |
        v
Dependency & lineage map
PostgreSQL views + BI + scripts + schedulers
        |
        v
Duplicate-candidate analysis
        |
        v
Choose canonical/current table
        |
        v
Migrate consumers to current table
        |
        v
Validate no old dependencies remain
        |
        v
zz_quarantine
10-working-day grace period
        |
        +---- dependency found ----> RESTORE
        |
        +---- approved + expired --> AUTOMATED DROP
```

## Audit Scope

### 1. Full database inventory

Collect for every user table:

- schema and table name;
- estimated row count;
- total table size;
- read activity;
- write activity;
- maintenance timestamps;
- statistics reset timestamp.

This produces a ranked inventory of the database and makes large, inactive, or suspicious objects visible.

### 2. Active vs inactive tables

The audit uses `pg_stat_user_tables` to inspect read/write signals, but does not treat `reads = 0` as absolute proof. Counters are interpreted relative to `stats_reset` and combined with dependency checks.

### 3. Dependency and lineage mapping

Internal PostgreSQL dependencies are mapped through `information_schema.view_table_usage`.

External consumers must also be checked separately, for example:

- Power BI datasets / PBIX files;
- Python scripts;
- ETL jobs;
- scheduled tasks;
- orchestration pipelines;
- other applications using schema-qualified table names.

The result is a practical lineage map: **who writes to a table, who reads from it, and what breaks if it disappears**.

### 4. Duplicate-candidate detection

The audit identifies likely duplicate families using metadata signals such as:

- similar normalized table names;
- `_copy`, `_backup`, `_old`, `_test`, `_tmp` suffixes;
- dated snapshots;
- similar row counts;
- similar table sizes.

Metadata similarity only produces **candidates**. True duplicates are confirmed separately using business keys, schema comparison, hashes, or `EXCEPT` checks.

### 5. Canonical table selection

For each duplicate or superseded family, one current table is selected as the canonical source.

A canonical table should be:

- current;
- actively maintained;
- reproducible from the correct upstream source;
- the table to which BI, scripts, and ETL should point going forward.

### 6. Consumer migration

Before retiring old tables, downstream consumers are migrated to the canonical table.

Migration is considered complete only after old references are removed from reports, scripts, views, and scheduled jobs.

### 7. Quarantine before deletion

Obsolete tables are not deleted immediately. They are moved into a dedicated `zz_quarantine` schema using `ALTER TABLE ... SET SCHEMA`.

This creates a controlled **scream test**: consumers referencing the old schema-qualified name fail and reveal hidden usage, while rollback remains fast because the data still exists.

### 8. Grace period and automated cleanup

Each quarantined table receives a `drop_after` date based on a 10-working-day grace period.

The automation is guarded: a table is deleted only when all conditions are true:

- `status = 'QUARANTINE'`;
- `drop_after <= CURRENT_DATE`;
- `approved_for_drop = true`.

The cleanup function intentionally avoids `CASCADE`. If a dependency blocks deletion, the attempt fails instead of recursively deleting dependent objects.

## Core PostgreSQL Checks

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

`reads = 0` only proves that no reads were recorded **since the last statistics reset**.

### View dependencies

```sql
SELECT view_schema, view_name
FROM information_schema.view_table_usage
WHERE table_schema = 'source_schema'
  AND table_name = 'table_name';
```

Views require a separate dependency check because PostgreSQL can keep them working after a table is moved to another schema.

## Decision Framework Before Quarantine

Before a table enters quarantine, answer:

1. Is anyone reading it?
2. Is anything writing to it?
3. Does it contain unique data?
4. Can it be rebuilt from an upstream source?
5. Does another table supersede it?
6. Have consumers been migrated to the current table?
7. Are all known dependencies documented?

A table becomes a retirement candidate only when the evidence supports that decision.

## Five Key Design Choices

| Design choice | What it does | Why it was selected |
| --- | --- | --- |
| Full inventory audit | Makes the whole database observable | Cleanup decisions are based on evidence, not table names alone |
| Dependency/lineage map | Shows consumers and upstream/downstream usage | Prevents deleting a table still used by BI, ETL, views, or scripts |
| Duplicate-candidate detection | Groups likely superseded copies | Helps consolidate consumers onto a canonical table |
| `ALTER TABLE ... SET SCHEMA zz_quarantine` | Moves a table into quarantine | Metadata-only, fast and reversible |
| Guarded scheduled cleanup | Deletes expired, explicitly approved objects | Automates lifecycle management without blind destructive behavior |

## Why Quarantine Instead of Immediate DROP?

| Alternative | Advantage | Main drawback | Decision |
| --- | --- | --- | --- |
| Immediate `DROP` | Simple and frees space immediately | Irreversible | Rejected without enough usage evidence |
| `pg_dump` then `DROP` | Backup exists | Slower restore for large tables | Extra safeguard, not primary rollback |
| Rename table in place | Reversible | Deprecated objects remain mixed with active ones | Less operationally clean |
| `REVOKE SELECT` | Table stays in place | Depends on separated roles/users | Weak when workloads share credentials |
| Cold storage then `DROP` | Good long-term retention option | More infrastructure, slower recovery | Better for unique history than obvious duplicates |
| **Audit + lineage + quarantine + guarded cleanup** | End-to-end and reversible | Requires disciplined evidence collection | Selected production approach |

## Safety Controls

- Never use `DROP ... CASCADE` in the retirement workflow.
- Check views separately before quarantine.
- Check reporting cycles before final deletion.
- Verify recoverability before deleting unique data.
- Do not infer duplicates only from similar names.
- Migrate consumers before retiring old tables.
- Require explicit approval before scheduled deletion.
- Keep an audit log after the physical table has been removed.
- Remember that quarantine does not free disk space; only `DROP` does.

## Known Limitations

1. PostgreSQL cannot automatically see every external PBIX, Python, scheduler, or application dependency.
2. Statistics can be incomplete after `stats_reset`.
3. Monthly consumers may be missed by a short observation window.
4. Duplicate detection by metadata only identifies candidates, not proof.
5. Shared database credentials reduce observability.
6. Automated deletion still requires governance: only approved objects are eligible.

## Repository Structure

```text
postgresql-table-quarantine/
├── README.md
├── sql/
│   ├── 01_create_quarantine.sql
│   ├── 02_candidate_checks.sql
│   ├── 03_quarantine_table.sql
│   ├── 04_restore_or_drop.sql
│   ├── 05_database_inventory_audit.sql
│   ├── 06_dependency_lineage_map.sql
│   ├── 07_duplicate_candidates.sql
│   └── 08_approved_auto_cleanup.sql
└── marketplace/
    ├── upwork-portfolio.md
    └── fiverr-gig.md
```

## Data Engineering Concepts Demonstrated

- Database auditing
- Data observability
- Data lineage
- Dependency analysis
- Data lifecycle management
- Canonical dataset selection
- Duplicate detection
- Consumer migration
- Scream testing
- Two-phase deletion
- Grace periods
- Audit logging
- Rollback planning
- Data retention policy
- Production-safe automation

## Interview Talking Points

Be ready to explain:

- How would you audit an unfamiliar PostgreSQL database before cleanup?
- How do you distinguish an inactive table from one whose statistics were reset?
- How do you find who reads from and writes to each table?
- How would you detect duplicate or superseded datasets?
- How do you choose a canonical table?
- How do you migrate BI and ETL consumers safely?
- Why quarantine before deletion?
- Why should automated deletion still require explicit approval?
- Why is rollback design as important as SQL itself?

## Why This Matters

This project is not only a table-cleanup script. It represents an end-to-end **database rationalization and data lifecycle project**: understand the estate, map usage, identify duplication, consolidate consumers, safely deprecate obsolete objects, and automate controlled retirement.

## Author

Anna Klymchuk  
Power BI / SQL / Data Engineering
