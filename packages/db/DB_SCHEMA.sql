-- PostgreSQL schema for Beauty Booking Mini App (Railway/Postgres)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE appointment_status AS ENUM ('pending','confirmed','cancelled','no_show','completed','moved');

CREATE TABLE IF NOT EXISTS clients (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    telegram_user_id BIGINT UNIQUE,
    phone           VARCHAR(30),
    first_name      VARCHAR(100),
    last_name       VARCHAR(100),
    username        VARCHAR(100),
    birthday        DATE,
    gender          VARCHAR(20),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS masters (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(150) NOT NULL,
    photo_url       TEXT,
    description     TEXT,
    specialties     TEXT[] DEFAULT '{}',
    active          BOOLEAN NOT NULL DEFAULT true,
    telegram_user_id BIGINT UNIQUE,
    phone           VARCHAR(30),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS services (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(200) UNIQUE NOT NULL,
    description     TEXT,
    category        VARCHAR(120),
    price_minor     INTEGER NOT NULL DEFAULT 0,
    duration_min    INTEGER NOT NULL CHECK (duration_min > 0),
    active          BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS master_services (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    master_id       UUID NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    service_id      UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
    custom_price_minor INTEGER,
    custom_duration_min INTEGER CHECK (custom_duration_min IS NULL OR custom_duration_min > 0),
    UNIQUE (master_id, service_id)
);

CREATE TABLE IF NOT EXISTS master_working_hours (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    master_id       UUID NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    weekday         SMALLINT NOT NULL CHECK (weekday BETWEEN 0 AND 6),
    start_time_min  INTEGER NOT NULL CHECK (start_time_min BETWEEN 0 AND 1440),
    end_time_min    INTEGER NOT NULL CHECK (end_time_min BETWEEN 0 AND 1440),
    break_start_min INTEGER,
    break_end_min   INTEGER,
    slot_step_min   INTEGER NOT NULL DEFAULT 30 CHECK (slot_step_min IN (10, 15, 20, 30, 60)),
    UNIQUE (master_id, weekday)
);

CREATE TABLE IF NOT EXISTS schedule_overrides (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    master_id       UUID NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    start_at        TIMESTAMPTZ NOT NULL,
    end_at          TIMESTAMPTZ NOT NULL,
    type            VARCHAR(20) NOT NULL CHECK (type IN ('closed','open','break')),
    note            TEXT
);

CREATE TABLE IF NOT EXISTS appointments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id       UUID NOT NULL REFERENCES clients(id) ON DELETE RESTRICT,
    master_id       UUID NOT NULL REFERENCES masters(id) ON DELETE RESTRICT,
    service_id      UUID NOT NULL REFERENCES services(id) ON DELETE RESTRICT,
    start_at        TIMESTAMPTZ NOT NULL,
    end_at          TIMESTAMPTZ NOT NULL,
    price_minor     INTEGER NOT NULL,
    status          appointment_status NOT NULL DEFAULT 'pending',
    comment         TEXT,
    created_by      VARCHAR(40) DEFAULT 'client',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_duration CHECK (end_at > start_at)
);

CREATE TABLE IF NOT EXISTS notifications_outbox (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    kind            VARCHAR(40) NOT NULL,
    channel_id      BIGINT,
    payload         JSONB NOT NULL,
    scheduled_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at         TIMESTAMPTZ,
    status          VARCHAR(20) NOT NULL DEFAULT 'queued',
    error           TEXT
);

CREATE TABLE IF NOT EXISTS loyalty_accounts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id       UUID UNIQUE NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    points          INTEGER NOT NULL DEFAULT 0,
    tier            VARCHAR(30) NOT NULL DEFAULT 'base',
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS loyalty_transactions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id      UUID NOT NULL REFERENCES loyalty_accounts(id) ON DELETE CASCADE,
    change_points   INTEGER NOT NULL,
    reason          VARCHAR(80) NOT NULL,
    appointment_id  UUID REFERENCES appointments(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS campaigns (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(200) NOT NULL,
    message         TEXT NOT NULL,
    filter_json     JSONB,
    scheduled_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS campaign_deliveries (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    campaign_id     UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    client_id       UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    status          VARCHAR(20) NOT NULL DEFAULT 'queued',
    error           TEXT,
    sent_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS analytics_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id       UUID,
    master_id       UUID,
    event_name      VARCHAR(100) NOT NULL,
    props           JSONB,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS experiments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key             VARCHAR(80) UNIQUE NOT NULL,
    enabled         BOOLEAN NOT NULL DEFAULT false,
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS experiment_variants (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    experiment_id   UUID NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    key             VARCHAR(40) NOT NULL,
    weight          INTEGER NOT NULL CHECK (weight >= 0),
    UNIQUE (experiment_id, key)
);

CREATE TABLE IF NOT EXISTS experiment_assignments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    experiment_id   UUID NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    client_id       UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    variant_key     VARCHAR(40) NOT NULL,
    assigned_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (experiment_id, client_id)
);

CREATE TABLE IF NOT EXISTS administrators (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    telegram_user_id BIGINT UNIQUE NOT NULL,
    name            VARCHAR(150),
    role            VARCHAR(40) NOT NULL DEFAULT 'admin'
);

CREATE INDEX IF NOT EXISTS idx_appointments_master_start ON appointments(master_id, start_at);
CREATE INDEX IF NOT EXISTS idx_appointments_client ON appointments(client_id, start_at);
CREATE INDEX IF NOT EXISTS idx_overrides_master_time ON schedule_overrides(master_id, start_at, end_at);
CREATE INDEX IF NOT EXISTS idx_services_active ON services(active);
CREATE INDEX IF NOT EXISTS idx_masters_active ON masters(active);
