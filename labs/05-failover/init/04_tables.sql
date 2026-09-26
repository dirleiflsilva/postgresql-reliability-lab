SET ROLE app_owner;

CREATE TABLE IF NOT EXISTS app.customers (
    customer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    document_number TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS app.addresses (
    address_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES app.customers(customer_id) ON DELETE CASCADE,
    street TEXT NOT NULL,
    city TEXT NOT NULL,
    state CHAR(2) NOT NULL,
    postal_code TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS app.categories (
    category_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS app.products (
    product_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id BIGINT NOT NULL REFERENCES app.categories(category_id),
    sku TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    price NUMERIC(12, 2) NOT NULL CHECK (price > 0),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS app.orders (
    order_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES app.customers(customer_id),
    order_number TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK (status IN ('pending', 'paid', 'cancelled', 'refunded')),
    ordered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0)
);

CREATE TABLE IF NOT EXISTS app.order_items (
    order_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES app.orders(order_id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES app.products(product_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price > 0),
    total_price NUMERIC(12, 2) GENERATED ALWAYS AS (quantity * unit_price) STORED
);

CREATE TABLE IF NOT EXISTS app.payments (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES app.orders(order_id) ON DELETE CASCADE,
    external_id UUID NOT NULL DEFAULT gen_random_uuid(),
    method TEXT NOT NULL CHECK (method IN ('credit_card', 'pix', 'bank_slip')),
    status TEXT NOT NULL CHECK (status IN ('authorized', 'captured', 'failed', 'refunded')),
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    paid_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS audit.events (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity_name TEXT NOT NULL,
    entity_id BIGINT NOT NULL,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_addresses_customer_id ON app.addresses(customer_id);
CREATE INDEX IF NOT EXISTS idx_products_category_id ON app.products(category_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON app.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_ordered_at ON app.orders(ordered_at);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON app.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON app.order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_payments_order_id ON app.payments(order_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_entity ON audit.events(entity_name, entity_id);

RESET ROLE;
