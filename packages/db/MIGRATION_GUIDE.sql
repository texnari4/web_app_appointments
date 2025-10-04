-- Migration helper
\i DB_SCHEMA.sql

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='appointments' AND column_name='telegram_user_id') THEN
        INSERT INTO clients(telegram_user_id, first_name, username)
        SELECT DISTINCT telegram_user_id, user_name, user_name
        FROM appointments
        ON CONFLICT (telegram_user_id) DO NOTHING;
    END IF;
END $$;
