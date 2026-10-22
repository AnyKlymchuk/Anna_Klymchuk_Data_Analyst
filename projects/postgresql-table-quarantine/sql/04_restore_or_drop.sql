-- PostgreSQL Table Quarantine
-- 04_restore_or_drop.sql
-- Replace source_schema and table_name before running.

-- Review quarantined tables
SELECT
    table_name,
    original_schema,
    quarantined_at,
    drop_after,
    drop_after - CURRENT_DATE AS days_left,
    status
FROM control.quarantine_log
WHERE status = 'QUARANTINE'
ORDER BY drop_after;

-- OPTION A: RESTORE if a dependency is discovered
-- ALTER TABLE zz_quarantine.table_name
-- SET SCHEMA source_schema;
--
-- UPDATE control.quarantine_log
-- SET status = 'RESTORED'
-- WHERE table_name = 'table_name'
--   AND status = 'QUARANTINE';

-- OPTION B: DROP only after the observation period and final checks
-- Important: do not use CASCADE.
-- DROP TABLE zz_quarantine.table_name;
--
-- UPDATE control.quarantine_log
-- SET status = 'DROPPED'
-- WHERE table_name = 'table_name'
--   AND status = 'QUARANTINE';
