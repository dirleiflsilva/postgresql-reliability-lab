CREATE INDEX perf_orders_pending ON app.orders(ordered_at, order_id) WHERE status = 'pending';
