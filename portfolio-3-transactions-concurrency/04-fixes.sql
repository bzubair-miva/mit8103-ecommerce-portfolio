-- =============================================================================
-- Farmily: 04-fixes.sql (Portfolio 3)
-- Three ways to stop the lost update from 03-lost-update.sql, where two buyers
-- both bought the last 50 kg of listing 3. Each fix repeats the same race.
--
-- Needs TWO psql sessions side by side:
--   docker exec -it farmily-pg psql -U postgres -d farmily
-- Run the steps IN ORDER, one at a time, in the window shown.
-- To keep the demos short, only the stock is shown. In the real app the order,
-- order line and payment would be inserted in the same transaction, as in
-- 01-commit.sql.
-- =============================================================================


-- #############################################################################
-- FIX A: PESSIMISTIC LOCKING WITH SELECT ... FOR UPDATE
-- Lock the row WHILE reading it, so the second buyer cannot read the stock
-- until the first buyer has finished.
-- #############################################################################

-- A0 | WINDOW 1 | Reset the stock to 50 kg
UPDATE produce_listings SET quantity_available = 50 WHERE listing_id = 3;

-- A1 | WINDOW 1 | Buyer A reads the stock AND locks the row (sees 50)
BEGIN;
SELECT quantity_available FROM produce_listings WHERE listing_id = 3 FOR UPDATE;

-- A2 | WINDOW 2 | Buyer B tries to read and lock the same row.
-- This WAITS (hangs) because Buyer A holds the lock.
BEGIN;
SELECT quantity_available FROM produce_listings WHERE listing_id = 3 FOR UPDATE;

-- A3 | WINDOW 1 | Buyer A buys 50 kg and commits
UPDATE produce_listings SET quantity_available = quantity_available - 50 WHERE listing_id = 3;
COMMIT;

-- Window 2 now un-freezes and shows 0.00: Buyer B sees the REAL stock.

-- A4 | WINDOW 2 | Not enough stock, so Buyer B's order is cancelled
ROLLBACK;


-- #############################################################################
-- FIX B: ATOMIC CONDITIONAL UPDATE
-- Check and reduce the stock in ONE statement. The database only reduces it
-- if enough is left at the moment of the update.
-- #############################################################################

-- B0 | WINDOW 1 | Reset the stock to 50 kg
UPDATE produce_listings SET quantity_available = 50 WHERE listing_id = 3;

-- B1 | WINDOW 1 | Buyer A reduces the stock only if 50 kg are available (UPDATE 1, 0.00 left)
BEGIN;
UPDATE produce_listings
SET quantity_available = quantity_available - 50
WHERE listing_id = 3 AND quantity_available >= 50
RETURNING quantity_available;

-- B2 | WINDOW 2 | Buyer B tries the same. This WAITS for Buyer A.
BEGIN;
UPDATE produce_listings
SET quantity_available = quantity_available - 50
WHERE listing_id = 3 AND quantity_available >= 50
RETURNING quantity_available;

-- B3 | WINDOW 1 | Buyer A commits
COMMIT;

-- Window 2 now finishes with UPDATE 0 and (0 rows): after Buyer A's commit the
-- row no longer has 50 kg, so the condition is false and nothing is changed.
-- The app sees "0 rows updated" and tells Buyer B the rice is sold out.

-- B4 | WINDOW 2 | Cancel Buyer B's order
ROLLBACK;


-- #############################################################################
-- FIX C: REPEATABLE READ ISOLATION
-- Both buyers make the same mistake as in 03-lost-update.sql (read 50, write 0),
-- but under REPEATABLE READ PostgreSQL detects that the row changed after
-- Buyer B read it, and rejects Buyer B's update.
-- #############################################################################

-- C0 | WINDOW 1 | Reset the stock to 50 kg
UPDATE produce_listings SET quantity_available = 50 WHERE listing_id = 3;

-- C1 | WINDOW 1 | Buyer A starts at REPEATABLE READ and reads the stock (50)
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT quantity_available FROM produce_listings WHERE listing_id = 3;

-- C2 | WINDOW 2 | Buyer B starts at REPEATABLE READ and reads the stock (also 50)
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT quantity_available FROM produce_listings WHERE listing_id = 3;

-- C3 | WINDOW 1 | Buyer A writes 0 (50 - 50, worked out by the app)
UPDATE produce_listings SET quantity_available = 0 WHERE listing_id = 3;

-- C4 | WINDOW 2 | Buyer B also writes 0. This WAITS for Buyer A.
UPDATE produce_listings SET quantity_available = 0 WHERE listing_id = 3;

-- C5 | WINDOW 1 | Buyer A commits
COMMIT;

-- Window 2 now fails with:
--   ERROR: could not serialize access due to concurrent update
-- The app must retry Buyer B's whole transaction, and on retry it reads 0.

-- C6 | WINDOW 2 | End Buyer B's failed transaction
ROLLBACK;

-- CHECK | EITHER WINDOW | After each fix, only 50 kg were sold: stock is 0.00
SELECT quantity_available FROM produce_listings WHERE listing_id = 3;
