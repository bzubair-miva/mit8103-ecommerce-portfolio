-- =============================================================================
-- Farmily: 01-commit.sql (Portfolio 3)
-- Demonstrates COMMIT: placing an order is ONE transaction. The order, its
-- order line, the stock reduction, the payment and the status change are all
-- saved together, or not at all.
--
-- Run in one psql session:  docker exec -it farmily-pg psql -U postgres -d farmily
-- currval(...) returns the order_id this session has just created.
-- =============================================================================

-- Setup: reset the test listing (listing 3, Ofada rice) to 50 kg
UPDATE produce_listings SET quantity_available = 50, listing_status = 'active' WHERE listing_id = 3;

BEGIN;

-- 1. Create the order for customer 42, delivered to one of their own addresses
INSERT INTO orders (customer_id, delivery_address_id)
VALUES (42, (SELECT min(address_id) FROM addresses WHERE customer_id = 42));

-- 2. Add the order line: 20 kg, at the listing's current price
INSERT INTO order_items (order_id, listing_id, quantity, unit_price_at_purchase)
SELECT currval(pg_get_serial_sequence('orders', 'order_id')), listing_id, 20, price_per_unit
FROM produce_listings WHERE listing_id = 3;

-- 3. Reduce the stock
UPDATE produce_listings SET quantity_available = quantity_available - 20 WHERE listing_id = 3;

-- 4. Record the payment
INSERT INTO payments (order_id, amount, payment_method, payment_status, transaction_reference)
SELECT currval(pg_get_serial_sequence('orders', 'order_id')), 20 * price_per_unit, 'card', 'completed',
       'TXDEMO-' || currval(pg_get_serial_sequence('orders', 'order_id'))
FROM produce_listings WHERE listing_id = 3;

-- 5. Mark the order as paid
UPDATE orders SET order_status = 'paid'
WHERE order_id = currval(pg_get_serial_sequence('orders', 'order_id'));

COMMIT;

-- Check: stock should now be 30.00, and the order should show as paid
SELECT quantity_available FROM produce_listings WHERE listing_id = 3;

SELECT o.order_id, o.order_status, oi.quantity, p.amount
FROM orders o
JOIN order_items oi USING (order_id)
JOIN payments p USING (order_id)
WHERE o.order_id = currval(pg_get_serial_sequence('orders', 'order_id'));
