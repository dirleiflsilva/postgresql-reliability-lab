CREATE TABLE audit.failover_probe (
    token TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE audit.failover_probe OWNER TO app_owner;
GRANT SELECT, INSERT, DELETE ON audit.failover_probe TO app_user;
GRANT SELECT ON audit.failover_probe TO readonly;
