-- =============================================================================
-- Farmily: 05-isolation-levels.sql (Portfolio 3)
-- Compares READ COMMITTED and REPEATABLE READ using a NON-REPEATABLE READ:
-- a buyer is checking out while the farmer changes the price of listing 3.
-- Does the buyer see the same price twice inside one transaction?
--
-- Needs TWO psql sessions side by side:
--   docker exec -it farmily-pg psql -U postgres -d farmily
-- Window 1 = buyer checking out. Window 2 = farmer editing the price.
-- Run the steps IN ORDER, one at a time, in the window shown.
-- =============================================================================


-- #############################################################################
-- PART 1: READ COMMITTED (PostgreSQL's default)
-- #############################################################################

-- 1.0 | WINDOW 2 | Set the price to 1,800 naira per kg
UPDATE produce_listings SET price_per_unit = 1800 WHERE listing_id = 3;

-- 1.1 | WINDOW 1 | Buyer starts checkout and reads the price (1800.00)
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT price_per_unit FROM produce_listings WHERE listing_id = 3;

-- 1.2 | WINDOW 2 | Farmer raises the price to 2,000 (saved immediately)
UPDATE produce_listings SET price_per_unit = 2000 WHERE listing_id = 3;

-- 1.3 | WINDOW 1 | Buyer reads the price again, in the SAME transaction
-- Result: 2000.00. The value changed mid-transaction (a non-repeatable read).
SELECT price_per_unit FROM produce_listings WHERE listing_id = 3;
COMMIT;


-- #############################################################################
-- PART 2: REPEATABLE READ
-- #############################################################################

-- 2.0 | WINDOW 2 | Set the price back to 1,800
UPDATE produce_listings SET price_per_unit = 1800 WHERE listing_id = 3;

-- 2.1 | WINDOW 1 | Buyer starts checkout at REPEATABLE READ (1800.00)
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT price_per_unit FROM produce_listings WHERE listing_id = 3;

-- 2.2 | WINDOW 2 | Farmer raises the price to 2,000 again
UPDATE produce_listings SET price_per_unit = 2000 WHERE listing_id = 3;

-- 2.3 | WINDOW 1 | Buyer reads the price again
-- Result: still 1800.00. The transaction sees a snapshot taken at its first
-- query, so its reads do not change while it runs.
SELECT price_per_unit FROM produce_listings WHERE listing_id = 3;
COMMIT;

-- 2.4 | WINDOW 1 | After COMMIT, a new statement sees the farmer's change (2000.00)
SELECT price_per_unit FROM produce_listings WHERE listing_id = 3;


-- Note: PostgreSQL never allows DIRTY READS (seeing another transaction's
-- uncommitted changes). Even if READ UNCOMMITTED is requested, it behaves as
-- READ COMMITTED.
