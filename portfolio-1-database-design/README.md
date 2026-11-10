# Portfolio 1: Database Design and Modelling

## What I did

I designed a relational database for Farmily, a marketplace that connects Nigerian farmers with household, restaurant and retail buyers. The design centres on the produce listing (a farmer's batch of a product), which links the catalogue, the stock and the orders, and it supports orders that contain produce from several farmers, each delivered separately. The result is a 13-table PostgreSQL schema in 3NF, with two deliberate exceptions (`orders` and `reviews`) explained under Notes.

## Files

- `design-decisions.md`: the entity list, the main design decisions (product versus batch, one delivery per farmer per order) and the domain constraints, split into those the tables enforce and those that need triggers or transactions.
- `farmily-erd.png` / `farmily-erd.drawio`: the conceptual ER diagram in Chen notation, as an image and as the editable draw.io source.
- `schema.sql`: the PostgreSQL 16 schema, with all 13 tables, keys and constraints.
- `normalisation.md`: a sample of order data taken from UNF through 1NF, 2NF and 3NF to BCNF, then matched against `schema.sql`.
- `schema-tables.png`: DBeaver after running `schema.sql`, showing the 13 tables in the `farmily` database.
- `test-customer-type.png`: DBeaver rejecting an invalid `customer_type` with a CHECK constraint error.
- `produce_listings_check.png`: DBeaver rejecting a produce listing whose expiry date is before its harvest date.
- `docker-view.png`: Docker Desktop showing the `farmily-pg` PostgreSQL container running on port 5432.

## How I implemented it

1. **Requirements:** I listed what Farmily needs to record (farmers, customers, products, harvested batches, orders, payments, deliveries, riders and reviews) and the questions that needed a design decision, recorded in `design-decisions.md`.
2. **ER diagram:** I drew the conceptual model in draw.io using Chen notation, showing entities, key attributes, relationships with cardinality, and participation (single and double lines). Only key attributes are shown to keep the diagram readable; the full attribute list is in `schema.sql` and `design-decisions.md`.
3. **Schema:** I turned the diagram into tables. Each 1:N relationship became a foreign key, and the M:N relationship between orders and listings became the `order_items` table. Business rules became CHECK, UNIQUE and foreign key constraints, including two composite foreign keys for rules that span two tables.
4. **Normalisation:** I checked the design by normalising sample order data to 3NF and confirming that every resulting table matches one in `schema.sql`.

**Tools:** draw.io for the ER diagram, PostgreSQL 16 running in Docker (container `farmily-pg`, port 5432), and DBeaver to run the scripts and view the database.

**Why the indexes are kept for Portfolio 2:** `schema.sql` creates only the indexes PostgreSQL adds automatically for primary keys and UNIQUE constraints. The extra indexes on foreign keys and common search columns are in `portfolio-2-query-optimisation/indexes.sql`, so that Portfolio 2 can measure the same queries before and after indexing and show the difference with `EXPLAIN ANALYZE`.

## How I tested it

1. **The schema runs:** I ran `schema.sql` against the `farmily` database in DBeaver. It completed without errors and created all 13 tables (`schema-tables.png`).
2. **Constraints reject invalid data:** I ran inserts that should fail:

```sql
-- Valid row, needed as setup: succeeds.
INSERT INTO regions (region_name) VALUES ('Lagos');

-- Should fail: 'business' is not an allowed customer_type
-- (allowed: 'household', 'restaurant', 'retailer').
INSERT INTO customers (name, customer_type, phone, email)
VALUES ('Test', 'business', '080', 'test@mail.com');

-- Should fail: expiry date (1 Nov) is before harvest date (10 Nov),
-- breaking CHECK (expiry_date > harvest_date).
INSERT INTO produce_listings (farmer_id, product_id, harvest_date, expiry_date, unit, price_per_unit, quantity_available)
VALUES (1, 1, '2026-11-10', '2026-11-01', 'kg', 1000, 5);
```

The customer insert was rejected with `SQL Error [23514]: new row for relation "customers" violates check constraint "customers_customer_type_check"` (`test-customer-type.png`). Error code 23514 is PostgreSQL's code for a CHECK violation, so the rule is enforced by the database itself, not by the application.

The produce listing insert, run on its own, was rejected with `SQL Error [23514]: new row for relation "produce_listings" violates check constraint "produce_listings_check"` (`produce_listings_check.png`). `produce_listings_check` is the name PostgreSQL gives automatically to the unnamed table-level `CHECK (expiry_date > harvest_date)`. The failing row in the error detail also shows the column defaults being applied (`grade` = A, `listing_status` = active), and the CHECK is tested before the foreign keys, so the rejection comes from the date rule itself.

## Notes

- `orders` keeps both `customer_id` and `delivery_address_id`, which is a deliberate exception to strict 3NF. A composite foreign key makes sure the address always belongs to the order's own customer (constraint 9 in `design-decisions.md`; see also `normalisation.md`, step 3).
- `reviews` follows the same pattern. When `listing_id` is filled in, it determines `farmer_id`, which is a transitive dependency. `farmer_id` is kept because a review can be about the farmer without naming a listing, and the composite foreign key `(listing_id, farmer_id)` (constraint 10) makes sure a named listing always belongs to the reviewed farmer. Reviews were not part of the normalisation sample, so this exception is recorded here.
- Rules that need data from other tables, such as stock availability and listing expiry at the time of purchase, cannot be CHECK constraints. They are listed in `design-decisions.md` (rules 14 to 18) and need triggers or transaction logic; safe concurrent stock updates are demonstrated in Portfolio 3.
