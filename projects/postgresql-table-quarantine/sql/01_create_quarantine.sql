-- PostgreSQL Table Quarantine
-- 01_create_quarantine.sql

CREATE SCHEMA IF NOT EXISTS zz_quarantine;

COMMENT ON SCHEMA zz_quarantine IS
'Quarantine for tables pending review before deletion.';

CREATE SCHEMA IF NOT EXISTS control;

CREATE TABLE IF NOT EXISTS control.quarantine_log (
    id              BIGSERIAL PRIMARY KEY,
    table_name      TEXT NOT NULL,
    original_schema TEXT NOT NULL,
    quarantined_at  DATE NOT NULL DEFAULT CURRENT_DATE,
    drop_after      DATE NOT NULL,
    reason          TEXT,
    status          TEXT NOT NULL DEFAULT 'QUARANTINE'
        CHECK (status IN ('QUARANTINE', 'RESTORED', 'DROPPED'))
);

COMMENT ON TABLE control.quarantine_log IS
'Audit log for PostgreSQL table quarantine decisions.';
