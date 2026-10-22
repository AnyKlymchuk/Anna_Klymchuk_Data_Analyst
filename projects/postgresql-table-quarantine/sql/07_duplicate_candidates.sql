-- Duplicate-candidate discovery
-- This script identifies likely duplicates by metadata signals.
-- It does NOT prove row-level duplication; business keys must be checked separately.

WITH tables AS (
    SELECT
        n.nspname AS schema_name,
        c.relname AS table_name,
        c.oid,
        c.reltuples::bigint AS rows_estimate,
        pg_total_relation_size(c.oid) AS total_bytes
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'zz_quarantine')
), normalized AS (
    SELECT
        *,
        regexp_replace(lower(table_name), '(_copy|_backup|_bak|_old|_test|_tmp|_[0-9]{4}(_[0-9]{2})?)$', '') AS normalized_name
    FROM tables
)
SELECT
    normalized_name,
    count(*) AS candidate_count,
    string_agg(schema_name || '.' || table_name, ', ' ORDER BY schema_name, table_name) AS candidate_tables,
    string_agg(pg_size_pretty(total_bytes), ', ' ORDER BY schema_name, table_name) AS sizes
FROM normalized
GROUP BY normalized_name
HAVING count(*) > 1
ORDER BY candidate_count DESC, normalized_name;

-- Next step for each candidate pair:
-- compare schema/columns, business keys, row counts, hashes or EXCEPT queries.
-- Only a row-level/business-key comparison can confirm that two tables are true duplicates.
