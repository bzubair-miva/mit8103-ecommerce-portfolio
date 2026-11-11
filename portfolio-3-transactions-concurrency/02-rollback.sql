-- =============================================================================
-- Farmily: 02-rollback.sql (Portfolio 3)
-- Demonstrates ROLLBACK and atomicity: an order for 40 kg when only 30 kg are
-- left. The stock UPDATE breaks CHECK (quantity_available >= 0), PostgreSQL
-- aborts the transaction, and ROLLBACK undoes the order and order line that
-- were inserted before the error.
--
-- Run in one psql session after 01-commit.sql (stock = 30 kg).
-- =============================================================================

BEGIN;

-- 1. Create the order (succeeds)
INSERT INTO orders (customer_id, delivery_address_id)
VALUES (42, (SELECT min(address_id) FROM addresses WHERE customer_id = 42));

-- 2. Add a 40 kg order line (succeeds)
INSERT INTO order_items (order_id, listing_id, quantity, unit_price_at_purchase)
SELECT currval(pg_get_serial_sequence('orders', 'order_id')), listing_id, 40, price_per_unit
FROM produce_listings WHERE listing_id = 3;

-- 3. Reduce the stock: FAILS, because 30 - 40 = -10 breaks
--    produce_listings_quantity_available_check
UPDATE produce_listings SET quantity_available = quantity_available - 40 WHERE listing_id = 3;

-- 4. Any further command is refused:
--    "current transaction is aborted, commands ignored until end of transaction block"
SELECT 1;

ROLLBACK;

-- Check: stock is still 30.00, and the order from step 1 no longer exists (0).
-- Its order_id number is used up anyway: sequences are not rolled back.
SELECT quantity_available FROM produce_listings WHERE listing_id = 3;

SELECT count(*) AS order_still_exists
FROM orders WHERE order_id = currval(pg_get_serial_sequence('orders', 'order_id'));
