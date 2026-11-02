CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE ROLE app_owner NOLOGIN;
CREATE ROLE app_user LOGIN PASSWORD :'app_password';
CREATE ROLE readonly LOGIN PASSWORD :'readonly_password';
CREATE ROLE monitor_user LOGIN PASSWORD :'monitor_password';
GRANT app_owner TO app_user;
GRANT pg_monitor TO monitor_user;

CREATE SCHEMA app AUTHORIZATION app_owner;
CREATE SCHEMA audit AUTHORIZATION app_owner;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE appdb TO app_user, readonly, monitor_user;
GRANT USAGE ON SCHEMA app, audit TO app_user, readonly;

SET ROLE app_owner;
CREATE TABLE app.customers (
    customer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE app.orders (
    order_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES app.customers(customer_id),
    order_number TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK (status IN ('pending', 'paid', 'cancelled')),
    total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
    ordered_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE audit.observability_probe (
    token TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX idx_orders_customer_id ON app.orders(customer_id);
CREATE INDEX idx_orders_ordered_at ON app.orders(ordered_at);

RESET ROLE;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_user;
GRANT SELECT, INSERT, DELETE ON audit.observability_probe TO app_user;
GRANT SELECT ON ALL TABLES IN SCHEMA app, audit TO readonly;

CREATE SCHEMA perf;
CREATE TABLE perf.dataset (
 id boolean PRIMARY KEY DEFAULT true CHECK(id), state text NOT NULL,
 manifest jsonb NOT NULL, started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 finished_at timestamptz
);
GRANT USAGE ON SCHEMA perf TO app_user;
GRANT SELECT ON perf.dataset TO app_user;
