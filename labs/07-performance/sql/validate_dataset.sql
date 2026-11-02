SELECT json_build_object(
 'customers', (SELECT count(*) FROM app.customers),
 'orders', (SELECT count(*) FROM app.orders),
 'statuses', (SELECT json_object_agg(status,n) FROM (SELECT status,count(*) n FROM app.orders GROUP BY status) s),
 'hot_orders', (SELECT count(*) FROM app.orders WHERE customer_id <= :customers / 10),
 'invalid', (SELECT count(*) FROM app.orders o LEFT JOIN app.customers c USING(customer_id)
 WHERE c.customer_id IS NULL OR total_amount < 0 OR ordered_at < :'reference'::timestamptz - interval '180 days' OR ordered_at > :'reference'::timestamptz),
 'bytes', pg_database_size(current_database()),
 'indexes', (SELECT json_object_agg(indexname,indexdef) FROM pg_indexes WHERE schemaname='app')
);
