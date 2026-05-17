WITH user_exposure AS (
    -- 1. Identify the first touchpoint and ensure no dual-exposure bugs
    SELECT 
        user_id,
        -- FIX: Renamed the output alias to avoid confusing BigQuery in the HAVING clause
        MAX(variant_group) AS final_variant_group, 
        MIN(timestamp) AS exposure_time
    FROM `abtest-496518.pdp_views.pdp_views` 
    GROUP BY user_id
    -- Now we can safely count the original column 
    HAVING COUNT(DISTINCT variant_group) = 1 
),

order_conversions AS (
    -- 2. Join the frontend views with backend orders and logistics
    SELECT 
        u.user_id,
        u.final_variant_group AS variant_group,
        COUNT(o.order_id) AS total_orders,
        MAX(CASE WHEN o.order_id IS NOT NULL THEN 1 ELSE 0 END) AS converted,
        -- Track SLA breaches for our critical guardrail metric
        SUM(CASE WHEN l.actual_delivery_date > l.promised_delivery_date THEN 1 ELSE 0 END) AS sla_breaches
    FROM user_exposure u
    -- LEFT JOIN ensures we keep users who didn't buy anything (conversion = 0)
    LEFT JOIN `abtest-496518.orders.orders` o 
        ON u.user_id = o.user_id AND o.timestamp >= u.exposure_time
    -- Join logistics data only for users who actually made an order
    LEFT JOIN `abtest-496518.delivery_performance.delivery_performance` l 
        ON o.order_id = l.order_id
    GROUP BY u.user_id, u.final_variant_group
)

-- 3. Aggregate the final metrics for our Power BI dashboard and Python analysis
SELECT 
    variant_group,
    COUNT(user_id) AS total_users,
    SUM(converted) AS total_conversions,
    ROUND(SUM(converted) / COUNT(user_id), 4) AS conversion_rate,
    SUM(sla_breaches) AS total_sla_breaches
FROM order_conversions
GROUP BY variant_group;