-- PostgreSQL Table Quarantine
-- 03_quarantine_table.sql
-- Replace source_schema and table_name before running.

ALTER TABLE source_schema.table_name
SET SCHEMA zz_quarantine;

INSERT INTO control.quarantine_log
    (table_name, original_schema, drop_after, reason)
SELECT
    'table_name',
    'source_schema',
    (
        SELECT d::date
        FROM generate_series(
            CURRENT_DATE + 1,
            CURRENT_DATE + 30,
            interval '1 day'
        ) d
        WHERE EXTRACT(ISODOW FROM d) < 6
        ORDER BY d
        OFFSET 9 LIMIT 1
    ),
    'Candidate validated: no confirmed active reads/writes; dependencies checked; recoverability confirmed.';

COMMENT ON TABLE zz_quarantine.table_name IS
'Table under quarantine pending final deletion review.';

SELECT
    table_name,
    original_schema,
    quarantined_at,
    drop_after,
    status
FROM control.quarantine_log
WHERE table_name = 'table_name'
ORDER BY id DESC
LIMIT 1;
