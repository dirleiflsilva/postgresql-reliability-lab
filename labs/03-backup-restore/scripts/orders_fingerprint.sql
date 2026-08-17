WITH fingerprint_rows AS (
    SELECT
        'orders' AS entity,
        order_id AS entity_id,
        concat_ws('|',
            customer_id::text,
            order_number,
            status,
            to_char(ordered_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'),
            total_amount::text
        ) AS payload
    FROM app.orders

    UNION ALL

    SELECT
        'order_items',
        order_item_id,
        concat_ws('|', order_id::text, product_id::text, quantity::text,
                  unit_price::text, total_price::text)
    FROM app.order_items

    UNION ALL

    SELECT
        'payments',
        payment_id,
        concat_ws('|', order_id::text, external_id::text, method, status,
                  amount::text,
                  COALESCE(to_char(paid_at AT TIME ZONE 'UTC',
                                   'YYYY-MM-DD"T"HH24:MI:SS.US'), '<null>'))
    FROM app.payments
)
SELECT md5(string_agg(entity || '|' || entity_id || '|' || payload,
                      E'\n' ORDER BY entity, entity_id))
FROM fingerprint_rows;
