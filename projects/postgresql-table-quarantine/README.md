# PostgreSQL Table Quarantine & Safe Cleanup

## Overview

This project demonstrates a safe, reversible workflow for identifying and removing unused PostgreSQL tables without immediately risking broken BI reports, ETL jobs, scripts, or downstream processes.

It is based on a real production-inspired data maintenance task. All company-specific names, infrastructure details, and sensitive identifiers have been anonymized.

## Business Problem

A PostgreSQL staging environment had accumulated many historical copies, test tables, snapshots, and one-off datasets. Some tables were large, but it was unclear which ones were still used by BI reports, scheduled scripts, views, or other processes.

Deleting tables immediately with `DROP TABLE` would be risky because:

- database usage statistics may have been reset;
- some dependencies may run only weekly or monthly;
- views may survive a schema move and therefore not reveal themselves during a scream test;
- a mistaken `DROP` is irreversible without restore from backup.

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

This is effectively a **two-phase delete** with a **grace period**, **audit log**, and explicit rollback path.

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

Views require a separate dependency check because PostgreSQL can keep them working after a table is moved to another schema.

## Five Key Design Choices

| Design choice | What it does | Why it was selected |
| --- | --- | --- |
| `ALTER TABLE ... SET SCHEMA zz_quarantine` | Moves a table into quarantine | Metadata-only change, fast and reversible; indexes and constraints move with the table |
| `pg_stat_user_tables` | Shows read/write activity | Gives evidence about whether a table is actively used without requiring extra extensions |
| `information_schema.view_table_usage` | Finds dependent views | Views may not fail after `SET SCHEMA`, so they must be checked separately |
| `control.quarantine_log` | Stores table, source schema, dates, reason, status | Creates a queryable audit trail that remains after the table is dropped |
| `generate_series` + `ISODOW < 6` | Calculates 10 working days | Automates a business-day grace period rather than using calendar days |

## Why This Approach Instead of the Alternatives?

| Alternative | Advantage | Main drawback | Decision |
| --- | --- | --- | --- |
| Immediate `DROP` | Simple and frees space immediately | Irreversible | Rejected because there was not enough evidence that a table was unused |
| `pg_dump` then `DROP` | Backup exists | Restoring a large table is slower than a metadata rollback | Used only as an extra safeguard for valuable data |
| Rename table in place | Reversible and can trigger failures | Deprecated tables remain mixed with active production tables | Rejected for operational clarity |
| `REVOKE SELECT` | Keeps table in place | Effective only when workloads use separate roles/users | Not suitable when workloads share one database user |
| Export to cold storage then `DROP` | Good long-term storage option | Requires additional infrastructure and slower recovery | More suitable for unique historical data than obvious duplicates |
| **Quarantine schema + audit log** | Reversible, centralized, documented | Disk space is not freed until final `DROP`; views need separate checks | Selected as the best balance of safety and simplicity |

A key lesson is that the correct approach depends on environment constraints. For example, `REVOKE SELECT` is attractive only when ETL, BI, and users have separate database roles.

## Quarantine Design

The workflow creates:

- `zz_quarantine` — temporary holding schema;
- `control.quarantine_log` — audit log;
- a 10-working-day observation window;
- explicit `QUARANTINE`, `RESTORED`, and `DROPPED` statuses;
- a no-`CASCADE` deletion rule as an additional safeguard.

## Example Lifecycle

Move a candidate:

```sql
ALTER TABLE source_schema.table_name
SET SCHEMA zz_quarantine;
```

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
- Check views separately before quarantine.
- Consider weekly and monthly reporting cycles before selecting the final deletion date.
- Avoid moving tables while BI refreshes or heavy queries are running because `ALTER TABLE` requires `ACCESS EXCLUSIVE` locking.
- Verify recoverability before deletion.
- For important datasets, create a backup/dump before final `DROP`.
- Remember that moving a table into quarantine does **not** free disk space; only final `DROP` does.

## Known Limitations

1. **Views do not necessarily "scream"** after a schema move, so view dependencies must be checked explicitly.
2. **Statistics may be incomplete** if PostgreSQL counters were reset; usage evidence is only valid after `stats_reset`.
3. **Monthly reports can be missed** by a short grace period; the deletion window should include at least one reporting cycle when relevant.
4. **Manual DROP can be forgotten**; a logical next improvement is automated reminders or a scheduled cleanup script.
5. **Shared database credentials reduce observability**; separate `etl_loader` and `powerbi_reader` roles would make lineage and access auditing stronger.

## Data Engineering Concepts Demonstrated

- **Scream test** — intentionally removing the original access path to reveal hidden consumers.
- **Soft delete / two-phase delete** — separating deprecation from physical deletion.
- **Grace period / deprecation window** — allowing time for hidden dependencies to appear.
- **Audit logging** — recording what changed, why, and with what outcome.
- **Data lifecycle management** — controlling transition from active data to archive and deletion.
- **Data lineage** — identifying who writes to and reads from a dataset.
- **Data retention policy** — defining how long data should be retained before deletion.

## Interview Talking Points

Be ready to explain:

- Why use `SET SCHEMA` instead of `DROP` after backup?
- How do you prove that a table is unused, and what does that evidence fail to cover?
- Why can a view continue to work after a schema move while a Power BI query can fail?
- What would change if ETL and reporting used separate PostgreSQL roles?
- Why is rollback design as important as the SQL itself in production data engineering?

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

- PostgreSQL and SQL
- Data lifecycle management
- Dependency analysis
- Production-safe database changes
- BI / ETL impact analysis
- Audit logging
- Rollback planning
- Data lineage thinking
- Risk-aware data engineering

## Why This Matters

This project shows more than writing SQL. It demonstrates a production mindset: gather evidence, understand dependencies, design rollback, document the decision, observe the result, and only then perform an irreversible cleanup.

## Author

Anna Klymchuk  
Power BI / SQL / Data Engineering
