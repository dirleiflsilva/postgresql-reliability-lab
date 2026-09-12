DO $validation$
BEGIN
    IF to_regclass('app.customers') IS NULL
        OR to_regclass('app.products') IS NULL
        OR to_regclass('app.orders') IS NULL
        OR to_regclass('app.order_items') IS NULL
        OR to_regclass('app.payments') IS NULL
        OR to_regclass('audit.events') IS NULL THEN
        RAISE EXCEPTION 'uma ou mais tabelas esperadas não foram restauradas';
    END IF;

    IF (SELECT count(*) FROM app.customers) < 100
        OR (SELECT count(*) FROM app.products) < 50
        OR (SELECT count(*) FROM app.orders) < 500 THEN
        RAISE EXCEPTION 'volume de dados restaurado abaixo do estado base esperado';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM app.customers
        WHERE email = 'customer1@example.com'
          AND document_number = '00000000001'
    ) THEN
        RAISE EXCEPTION 'cliente sentinela não foi restaurado corretamente';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM app.products
        WHERE sku = 'SKU-00001'
          AND name = 'Product 1'
          AND price > 0
    ) THEN
        RAISE EXCEPTION 'produto sentinela não foi restaurado corretamente';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM app.orders
        WHERE order_number = 'ORD-00000001'
          AND total_amount > 0
    ) THEN
        RAISE EXCEPTION 'pedido sentinela não foi restaurado corretamente';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM app.orders AS o
        LEFT JOIN app.order_items AS oi ON oi.order_id = o.order_id
        GROUP BY o.order_id, o.total_amount
        HAVING o.total_amount <> COALESCE(sum(oi.total_price), 0)
    ) THEN
        RAISE EXCEPTION 'total de pedido diverge da soma dos itens';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM app.payments AS p
        JOIN app.orders AS o ON o.order_id = p.order_id
        WHERE p.amount <> o.total_amount
    ) THEN
        RAISE EXCEPTION 'valor de pagamento diverge do total do pedido';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'app.orders'::regclass
          AND contype = 'p'
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'app.order_items'::regclass
          AND confrelid = 'app.orders'::regclass
          AND contype = 'f'
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'app.payments'::regclass
          AND confrelid = 'app.orders'::regclass
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION 'constraints essenciais não foram restauradas';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_index
        WHERE indexrelid = 'app.idx_orders_ordered_at'::regclass
          AND indisvalid
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_index
        WHERE indexrelid = 'app.idx_order_items_order_id'::regclass
          AND indisvalid
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_index
        WHERE indexrelid = 'app.idx_payments_order_id'::regclass
          AND indisvalid
    ) THEN
        RAISE EXCEPTION 'índices essenciais ausentes ou inválidos';
    END IF;

    IF (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'app') <> 'app_owner'
        OR (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'audit') <> 'app_owner'
        OR (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'seed') <> 'app_owner'
        OR (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid = 'app.orders'::regclass) <> 'app_owner'
        OR (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid = 'audit.events'::regclass) <> 'app_owner' THEN
        RAISE EXCEPTION 'ownership de schemas ou tabelas não foi preservado';
    END IF;

    IF NOT has_table_privilege('app_user', 'app.orders', 'SELECT')
        OR NOT has_table_privilege('app_user', 'app.orders', 'INSERT')
        OR NOT has_table_privilege('readonly', 'app.orders', 'SELECT')
        OR has_table_privilege('readonly', 'app.orders', 'INSERT')
        OR NOT has_schema_privilege('readonly', 'app', 'USAGE') THEN
        RAISE EXCEPTION 'privilégios essenciais não foram preservados';
    END IF;
END
$validation$;
