CREATE INDEX perf_orders_history ON app.orders(customer_id, ordered_at DESC, order_id DESC);
