-- PostgreSQL Table Quarantine
-- 02_candidate_checks.sql

-- 1. Table size, estimated rows, reads and writes
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

-- 2. Check when database statistics were reset
SELECT stats_reset
FROM pg_stat_database
WHERE datname = current_database();

-- 3. Check view dependencies before quarantine
-- Replace source_schema and table_name.
SELECT view_schema, view_name
FROM information_schema.view_table_usage
WHERE table_schema = 'source_schema'
  AND table_name = 'table_name';

-- 4. Optional: compare candidate with its replacement/current table.
-- Adapt keys and selected columns to the actual data model.
--
-- SELECT key_column
-- FROM source_schema.candidate_table
-- EXCEPT
-- SELECT key_column
-- FROM source_schema.current_table;
