-- Dependency / lineage map inside PostgreSQL
-- Shows which views depend on which base tables.

SELECT
    u.table_schema AS source_schema,
    u.table_name   AS source_table,
    u.view_schema,
    u.view_name
FROM information_schema.view_table_usage u
ORDER BY u.table_schema, u.table_name, u.view_schema, u.view_name;

-- For a single table:
-- SELECT view_schema, view_name
-- FROM information_schema.view_table_usage
-- WHERE table_schema = 'source_schema'
--   AND table_name = 'table_name';

-- NOTE:
-- External consumers such as Power BI files, Python scripts, scheduled jobs,
-- and orchestration tools must be scanned separately because PostgreSQL
-- cannot see all file-level or application-level references by itself.
