WITH active_users AS (
    SELECT
        user_id,
        email,
        country_code,
        created_at
    FROM users
    WHERE is_active = TRUE
),

user_order_stats AS (
    SELECT
        user_id,
        COUNT(order_id)        AS total_orders,
        SUM(amount)            AS total_spent,
        MAX(created_at)        AS last_order_date,
        MIN(created_at)        AS first_order_date
    FROM orders
    GROUP BY user_id
)

SELECT
    u.user_id,
    u.email,
    u.country_code,
    u.created_at                            AS user_created_at,
    COALESCE(s.total_orders, 0)             AS total_orders,
    COALESCE(s.total_spent, 0.0)            AS total_spent,
    s.last_order_date,
    s.first_order_date,
    s.last_order_date - s.first_order_date  AS order_tenure_days
FROM active_users u
LEFT JOIN user_order_stats s ON u.user_id = s.user_id
