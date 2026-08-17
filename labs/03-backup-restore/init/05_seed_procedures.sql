SET ROLE app_owner;

CREATE OR REPLACE PROCEDURE seed.load_sample_data(
    p_customers INTEGER DEFAULT 100,
    p_categories INTEGER DEFAULT 5,
    p_products INTEGER DEFAULT 50,
    p_orders INTEGER DEFAULT 500
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id BIGINT;
    v_customer_id BIGINT;
    v_product_id BIGINT;
    v_quantity INTEGER;
    v_unit_price NUMERIC(12, 2);
    v_total_amount NUMERIC(12, 2);
    v_status TEXT;
    v_payment_status TEXT;
BEGIN
    INSERT INTO app.categories (name)
    SELECT 'Category ' || gs
    FROM generate_series(1, p_categories) AS gs
    ON CONFLICT (name) DO NOTHING;

    INSERT INTO app.customers (full_name, email, document_number, created_at)
    SELECT
        'Customer ' || gs,
        'customer' || gs || '@example.com',
        lpad(gs::text, 11, '0'),
        now() - (random() * interval '180 days')
    FROM generate_series(1, p_customers) AS gs
    ON CONFLICT (email) DO NOTHING;

    INSERT INTO app.addresses (customer_id, street, city, state, postal_code)
    SELECT
        c.customer_id,
        'Street ' || c.customer_id,
        (ARRAY['Sao Paulo', 'Rio de Janeiro', 'Belo Horizonte', 'Curitiba', 'Recife'])[floor(random() * 5 + 1)],
        (ARRAY['SP', 'RJ', 'MG', 'PR', 'PE'])[floor(random() * 5 + 1)],
        lpad(c.customer_id::text, 8, '0')
    FROM app.customers c
    WHERE NOT EXISTS (
        SELECT 1
        FROM app.addresses a
        WHERE a.customer_id = c.customer_id
    );

    INSERT INTO app.products (category_id, sku, name, price, active)
    SELECT
        ((gs - 1) % p_categories) + 1,
        'SKU-' || lpad(gs::text, 5, '0'),
        'Product ' || gs,
        round((random() * 490 + 10)::numeric, 2),
        true
    FROM generate_series(1, p_products) AS gs
    ON CONFLICT (sku) DO NOTHING;

    FOR i IN 1..p_orders LOOP
        SELECT customer_id
        INTO v_customer_id
        FROM app.customers
        ORDER BY random()
        LIMIT 1;

        v_status := (ARRAY['pending', 'paid', 'paid', 'paid', 'cancelled'])[floor(random() * 5 + 1)];

        INSERT INTO app.orders (customer_id, order_number, status, ordered_at)
        VALUES (
            v_customer_id,
            'ORD-' || lpad(i::text, 8, '0'),
            v_status,
            now() - (random() * interval '90 days')
        )
        ON CONFLICT (order_number) DO NOTHING
        RETURNING order_id INTO v_order_id;

        IF v_order_id IS NULL THEN
            CONTINUE;
        END IF;

        v_total_amount := 0;

        FOR item_number IN 1..(floor(random() * 4 + 1)::integer) LOOP
            SELECT product_id, price
            INTO v_product_id, v_unit_price
            FROM app.products
            ORDER BY random()
            LIMIT 1;

            v_quantity := floor(random() * 3 + 1)::integer;

            INSERT INTO app.order_items (order_id, product_id, quantity, unit_price)
            VALUES (v_order_id, v_product_id, v_quantity, v_unit_price);

            v_total_amount := v_total_amount + (v_quantity * v_unit_price);
        END LOOP;

        UPDATE app.orders
        SET total_amount = v_total_amount
        WHERE order_id = v_order_id;

        IF v_status = 'paid' THEN
            v_payment_status := 'captured';
        ELSIF v_status = 'cancelled' THEN
            v_payment_status := 'failed';
        ELSE
            v_payment_status := 'authorized';
        END IF;

        INSERT INTO app.payments (order_id, method, status, amount, paid_at)
        VALUES (
            v_order_id,
            (ARRAY['credit_card', 'pix', 'bank_slip'])[floor(random() * 3 + 1)],
            v_payment_status,
            v_total_amount,
            CASE WHEN v_status = 'paid' THEN now() - (random() * interval '90 days') ELSE NULL END
        );

        INSERT INTO audit.events (entity_name, entity_id, event_type, payload)
        VALUES (
            'order',
            v_order_id,
            'created',
            jsonb_build_object('order_number', 'ORD-' || lpad(i::text, 8, '0'), 'status', v_status)
        );
    END LOOP;
END;
$$;

RESET ROLE;

GRANT EXECUTE ON PROCEDURE seed.load_sample_data(INTEGER, INTEGER, INTEGER, INTEGER) TO app_user;
