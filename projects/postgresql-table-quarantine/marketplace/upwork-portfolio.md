# Upwork Portfolio Project

## Title
PostgreSQL Database Cleanup & Safe Table Quarantine Workflow

## Role
SQL / PostgreSQL Data Engineer

## Project Description
I designed a safe PostgreSQL cleanup workflow for a database where historical copies, test tables, snapshots, and obsolete datasets had accumulated over time.

The main challenge was that tables could not simply be deleted: some might still be used by Power BI reports, scheduled scripts, ETL jobs, or database views, while PostgreSQL usage statistics could be incomplete after a statistics reset.

I implemented a reversible quarantine process instead of immediate deletion.

### What I built
- analyzed table size, estimated row counts, reads, and writes;
- checked PostgreSQL statistics reset history;
- reviewed view dependencies and external script references;
- created a dedicated `zz_quarantine` schema;
- built an audit table to log every quarantine decision;
- implemented a defined observation period before deletion;
- created restore and final DROP procedures;
- added safeguards such as avoiding `DROP ... CASCADE`;
- documented operational risks, locks, rollback, and monthly reporting dependencies.

### Result
The process turns risky database cleanup into a controlled lifecycle: validate → quarantine → observe → restore or delete.

This approach is useful for PostgreSQL environments connected to BI reporting, ETL pipelines, analytics applications, and large staging databases.

## Skills
PostgreSQL, SQL, Data Engineering, Database Cleanup, ETL, Power BI, Data Lifecycle Management, Dependency Analysis, Data Quality, Automation
