CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO users (name, email)
VALUES
    ('Alice Reliability', 'alice@example.com'),
    ('Bruno Ops', 'bruno@example.com'),
    ('Carla Platform', 'carla@example.com')
ON CONFLICT (email) DO NOTHING;
