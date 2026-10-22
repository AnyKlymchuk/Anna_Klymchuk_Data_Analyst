-- Full PostgreSQL database inventory audit
-- Anonymized portfolio script.

SELECT
    s.schemaname,
    s.relname AS table_name,
    c.reltuples::bigint AS rows_estimate,
    pg_total_relation_size(s.relid) AS total_bytes,
    pg_size_pretty(pg_total_relation_size(s.relid)) AS total_size,
    COALESCE(s.seq_scan, 0) + COALESCE(s.idx_scan, 0) AS reads,
    COALESCE(s.n_tup_ins, 0) + COALESCE(s.n_tup_upd, 0) + COALESCE(s.n_tup_del, 0) AS writes,
    s.last_vacuum,
    s.last_autovacuum,
    s.last_analyze,
    s.last_autoanalyze
FROM pg_stat_user_tables s
JOIN pg_class c ON c.oid = s.relid
ORDER BY pg_total_relation_size(s.relid) DESC;

-- Statistics reset point: usage counters are only meaningful after this timestamp.
SELECT stats_reset
FROM pg_stat_database
WHERE datname = current_database();
