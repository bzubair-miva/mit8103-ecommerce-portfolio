-- =============================================================================
-- Farmily: 03-lost-update.sql (Portfolio 3)
-- Demonstrates a LOST UPDATE: two buyers buy the last 50 kg of Ofada rice
-- (listing 3) at the same time, and Farmily sells 100 kg it does not have.
--
-- Needs TWO psql sessions side by side:
--   docker exec -it farmily-pg psql -U postgres -d farmily
-- Run the steps IN ORDER, one at a time, in the window shown.
-- Isolation level: READ COMMITTED (PostgreSQL's default).
-- =============================================================================


-- STEP 0 | WINDOW 1 | Reset the stock to 50 kg
UPDATE produce_listings SET quantity_available = 50 WHERE listing_id = 3;


-- STEP 1 | WINDOW 1 | Buyer A starts and checks the stock (sees 50)
BEGIN;
SELECT quantity_available FROM produce_listings WHERE listing_id = 3;


-- STEP 2 | WINDOW 2 | Buyer B starts at the same moment and checks the stock (also sees 50)
BEGIN;
SELECT quantity_available FROM produce_listings WHERE listing_id = 3;


-- STEP 3 | WINDOW 1 | Buyer A orders all 50 kg.
-- The "app" works out the new stock itself (50 - 50 = 0) and writes it back.
INSERT INTO orders (customer_id, delivery_address_id)
VALUES (42, (SELECT min(address_id) FROM addresses WHERE customer_id = 42));
INSERT INTO order_items (order_id, listing_id, quantity, unit_price_at_purchase)
SELECT currval(pg_get_serial_sequence('orders', 'order_id')), 3, 50, price_per_unit
FROM produce_listings WHERE listing_id = 3;
UPDATE produce_listings SET quantity_available = 0 WHERE listing_id = 3;


-- STEP 4 | WINDOW 2 | Buyer B also orders 50 kg, based on the 50 it read in step 2.
-- The final UPDATE WAITS (hangs), because Window 1 has locked the row.
INSERT INTO orders (customer_id, delivery_address_id)
VALUES (42, (SELECT min(address_id) FROM addresses WHERE customer_id = 42));
INSERT INTO order_items (order_id, listing_id, quantity, unit_price_at_purchase)
SELECT currval(pg_get_serial_sequence('orders', 'order_id')), 3, 50, price_per_unit
FROM produce_listings WHERE listing_id = 3;
UPDATE produce_listings SET quantity_available = 0 WHERE listing_id = 3;


-- STEP 5 | WINDOW 1 | Buyer A commits.
-- Window 2's UPDATE now finishes (UPDATE 1).
COMMIT;


-- STEP 6 | WINDOW 2 | Buyer B commits
COMMIT;


-- STEP 7 | WINDOW 1 or 2 | Check the result
-- Expected: stock = 0, but 2 orders and 100 kg sold from a 50 kg batch.
SELECT quantity_available FROM produce_listings WHERE listing_id = 3;

SELECT count(*) AS orders, sum(oi.quantity) AS kg_sold
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE oi.listing_id = 3
  AND o.order_date > now() - INTERVAL '10 minutes';
