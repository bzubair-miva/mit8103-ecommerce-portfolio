-- =============================================================================
-- Farmily: queries.sql (Portfolio 2)
-- Six everyday queries, two each for a buyer, a farmer and an admin.
-- Run after schema.sql and sample-data.sql. To see how PostgreSQL runs a query,
-- put EXPLAIN ANALYZE in front of it.
--
-- "Today" is fixed at 2026-11-10 (the date the sample data is built around),
-- so results and plans are repeatable.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- BUYER
-- -----------------------------------------------------------------------------

-- Q1: A buyer searches for active, unexpired Ofada rice, cheapest first.
SELECT l.listing_id, f.name AS farmer, l.grade, l.price_per_unit, l.quantity_available
FROM produce_listings l
JOIN farmers f ON f.farmer_id = l.farmer_id
WHERE l.product_id = 1
  AND l.listing_status = 'active'
  AND l.expiry_date > DATE '2026-11-10'
ORDER BY l.price_per_unit;

-- Q2: A buyer (customer 42) views their order history, newest first,
--     with each order's total calculated from its order lines.
SELECT o.order_id, o.order_date, o.order_status,
       count(*)                                      AS lines,
       round(sum(oi.quantity * oi.unit_price_at_purchase), 2)  AS order_total
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 42
GROUP BY o.order_id, o.order_date, o.order_status
ORDER BY o.order_date DESC;


-- -----------------------------------------------------------------------------
-- FARMER
-- -----------------------------------------------------------------------------

-- Q3: A farmer (farmer 5) checks which of their active listings expire in the
--     next 14 days and still have stock, so they can discount them.
SELECT l.listing_id, p.product_name, l.grade, l.expiry_date,
       l.quantity_available, l.unit, l.price_per_unit
FROM produce_listings l
JOIN products p ON p.product_id = l.product_id
WHERE l.farmer_id = 5
  AND l.listing_status = 'active'
  AND l.quantity_available > 0
  AND l.expiry_date BETWEEN DATE '2026-11-10' AND DATE '2026-11-10' + 14
ORDER BY l.expiry_date;

-- Q4: A farmer (farmer 5) sees their sales per product over the last 90 days,
--     excluding cancelled orders.
SELECT p.product_name,
       count(DISTINCT o.order_id)                    AS orders,
       sum(oi.quantity)                              AS quantity_sold,
       round(sum(oi.quantity * oi.unit_price_at_purchase), 2)  AS revenue
FROM produce_listings l
JOIN products p     ON p.product_id = l.product_id
JOIN order_items oi ON oi.listing_id = l.listing_id
JOIN orders o       ON o.order_id = oi.order_id
WHERE l.farmer_id = 5
  AND o.order_status <> 'cancelled'
  AND o.order_date >= TIMESTAMPTZ '2026-11-10' - INTERVAL '90 days'
GROUP BY p.product_name
ORDER BY revenue DESC;


-- -----------------------------------------------------------------------------
-- ADMIN
-- -----------------------------------------------------------------------------

-- Q5: An admin lists the 10 best-rated verified farmers with at least
--     5 reviews. average_rating is derived here, not stored.
SELECT f.farmer_id, f.name, r.region_name,
       count(*)                     AS reviews,
       round(avg(rv.rating), 2)     AS average_rating
FROM farmers f
JOIN regions r  ON r.region_id = f.region_id
JOIN reviews rv ON rv.farmer_id = f.farmer_id
WHERE f.is_verified
GROUP BY f.farmer_id, f.name, r.region_name
HAVING count(*) >= 5
ORDER BY average_rating DESC, reviews DESC
LIMIT 10;

-- Q6: An admin finds parcels dispatched in the last 30 days that are still in
--     transit more than 3 days later, with the rider to chase and the
--     customer's region.
SELECT d.delivery_id, d.order_id, d.dispatched_date,
       DATE '2026-11-10' - d.dispatched_date::date  AS days_in_transit,
       rd.name  AS rider, rd.phone AS rider_phone,
       rg.region_name AS delivery_region
FROM deliveries d
JOIN riders rd    ON rd.rider_id = d.rider_id
JOIN orders o     ON o.order_id = d.order_id
JOIN addresses a  ON a.address_id = o.delivery_address_id
JOIN regions rg   ON rg.region_id = a.region_id
WHERE d.tracking_status = 'in_transit'
  AND d.dispatched_date >= TIMESTAMPTZ '2026-11-10' - INTERVAL '30 days'
  AND d.dispatched_date <  TIMESTAMPTZ '2026-11-10' - INTERVAL '3 days'
ORDER BY d.dispatched_date;
