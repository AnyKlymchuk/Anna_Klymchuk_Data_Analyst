-- Guarded automatic cleanup for quarantined tables.
-- A table is eligible only when:
--   1) it is still in QUARANTINE status;
--   2) drop_after has passed;
--   3) approved_for_drop = true.
-- Schedule this function externally (for example, an approved scheduler) once per day.

ALTER TABLE control.quarantine_log
ADD COLUMN IF NOT EXISTS approved_for_drop boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION control.cleanup_approved_quarantine()
RETURNS TABLE(table_name text, result text)
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT id, table_name
        FROM control.quarantine_log
        WHERE status = 'QUARANTINE'
          AND drop_after <= CURRENT_DATE
          AND approved_for_drop = true
        ORDER BY drop_after, id
    LOOP
        BEGIN
            -- Intentionally no CASCADE.
            EXECUTE format('DROP TABLE zz_quarantine.%I', r.table_name);

            UPDATE control.quarantine_log
            SET status = 'DROPPED'
            WHERE id = r.id;

            table_name := r.table_name;
            result := 'DROPPED';
            RETURN NEXT;
        EXCEPTION WHEN OTHERS THEN
            table_name := r.table_name;
            result := 'FAILED: ' || SQLERRM;
            RETURN NEXT;
        END;
    END LOOP;
END;
$$;

-- Preview before scheduling:
SELECT table_name, original_schema, drop_after, approved_for_drop
FROM control.quarantine_log
WHERE status = 'QUARANTINE'
  AND drop_after <= CURRENT_DATE
ORDER BY drop_after;

-- Manual execution / scheduler target:
-- SELECT * FROM control.cleanup_approved_quarantine();
