CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE ROLE app_owner NOLOGIN;
CREATE ROLE app_user LOGIN PASSWORD 'app_user_password';
CREATE ROLE readonly LOGIN PASSWORD 'readonly_password';
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

INSERT INTO app.customers (full_name, email, created_at)
SELECT 'Customer ' || n, 'customer' || n || '@example.com', now() - random() * interval '180 days'
FROM generate_series(1, 100) AS n;
INSERT INTO app.orders (customer_id, order_number, status, total_amount, ordered_at)
SELECT 1 + ((n - 1) % 100), 'ORD-' || lpad(n::text, 8, '0'),
       (ARRAY['pending','paid','paid','cancelled'])[1 + (n % 4)],
       round((10 + random() * 990)::numeric, 2), now() - random() * interval '90 days'
FROM generate_series(1, 500) AS n;
RESET ROLE;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_user;
GRANT SELECT, INSERT, DELETE ON audit.observability_probe TO app_user;
GRANT SELECT ON ALL TABLES IN SCHEMA app, audit TO readonly;
