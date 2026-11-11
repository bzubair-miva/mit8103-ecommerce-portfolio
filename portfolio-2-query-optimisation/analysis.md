# Farmily: Query and Performance Analysis

## 1. Summary

Execution times are taken from the `EXPLAIN ANALYZE` output in `plans/before/` and `plans/after/`.

| Query | Before | After | Speed-up | Main plan change |
|---|---|---|---|---|
| Q1: rice search | 4.4 ms | 2.9 ms | ~1.5× | Seq Scan → Bitmap Index Scan (`idx_listings_active`) |
| Q2: order history | 6.9 ms | 0.8 ms | ~8× | Seq Scan on orders → `idx_orders_customer` |
| Q3: expiring stock | 1.9 ms | 0.9 ms | ~2× | full scan of the `(listing_id, farmer_id)` index → `idx_listings_farmer` |
| Q4: farmer sales | 32.5 ms | 10.7 ms | ~3× | Seq Scan of 150,085 order_items + hash join → `idx_order_items_listing` lookups (54 loops) |
| Q5: top farmers | 15.0 ms | 13.8 ms | none | unchanged: Seq Scan is still cheapest |
| Q6: stuck parcels | 27.5 ms | 18.3 ms | ~1.5× | Seq Scan on deliveries → `idx_deliveries_in_transit` |

## 2. Query by query

**Q1: rice search (buyer).** The partial index `idx_listings_active` replaced the sequential scan, which had read all 20,000 listings and thrown away 17,894 of them. The gain is modest because Ofada rice is the most popular product: 2,106 rows (about 10% of the table) still match, spread over 195 heap blocks, and they still have to be joined to farmers and sorted by price. An index pays off most when it lets the database skip most of the table, and here it can only skip about 90%. The plan also shows an estimation error: the planner expected 433 rows but got 2,106. It treats the three conditions (product, status and expiry date) as independent and multiplies their selectivities, but in this data `listing_status = 'active'` and `expiry_date > today` are strongly correlated, because expired listings are marked `expired`. Multiplying the two therefore underestimates the result.

**Q2: order history (buyer).** This is the clearest win. Before the index, PostgreSQL read all 50,000 orders and discarded 49,994 to find customer 42's six. `idx_orders_customer` takes it straight to those six rows, which sit in just six heap blocks, so the query went from 6.9 ms to 0.8 ms. This is a highly selective condition (6 out of 50,000), the case indexes are best at. The second step, fetching each order's lines, was already fast in the before plan, because the `UNIQUE (order_id, listing_id)` constraint on order_items creates an index whose first column is `order_id`.

**Q3: expiring stock (farmer).** Even the before plan used an index, but not efficiently. The only index containing `farmer_id` was the one PostgreSQL built for `UNIQUE (listing_id, farmer_id)`, where `farmer_id` is the second column. A B-tree is sorted by its first column, so the database cannot jump to farmer 5's entries and has to read the whole index to find them. `idx_listings_farmer` has `farmer_id` first, so the after plan goes straight to farmer 5's 54 listings. The lesson is that column order in a composite index matters: an index helps a search on its leading column, not on a later one.

**Q4: farmer sales (farmer).** Before the indexes, there was no quick way to find the order lines for one farmer's listings. The planner found farmer 5's 54 listings by scanning all 20,000, then read all 150,085 order items and used a hash join to keep the 366 that matched. Reading everything once and joining in memory was the cheapest option, because any other approach would have meant scanning order_items once per listing. Once `idx_order_items_listing` existed, a nested loop became cheaper: for each of the 54 listings (`loops=54` in the plan) it looks up that listing's order lines in the index, about 7 each, and never touches the other 149,000 rows. It still takes 10.7 ms because the remaining work is fetching scattered rows: the 366 matching order lines sit in 363 different heap blocks, and each one then needs its own lookup in `orders` (366 index lookups). Adding the index changed the join algorithm, not just the scan: a hash join suits large inputs on both sides, while a nested loop with index lookups suits a small outer input with an index on the inner table.

**Q5: top farmers (admin).** The plan is identical before and after; the small difference in time is run-to-run noise. `idx_reviews_farmer` exists, but the optimiser correctly ignores it, because the query needs the reviews of every verified farmer: 18,886 of the 20,793 reviews, about 91%. Reading 91% of a table through an index means jumping between index and table thousands of times, which is slower than reading the table once in order, so a sequential scan and hash join remain the cheapest plan. The real fix for this kind of query is to stop recalculating it every time, for example with a materialised view that stores each farmer's review count and average rating. The trade-off is freshness and upkeep: the view only changes when it is refreshed (`REFRESH MATERIALIZED VIEW`), so new reviews are not included until then, and each refresh does the full calculation again. It is a controlled exception to the Portfolio 1 decision not to store derived values such as `average_rating`.

**Q6: stuck parcels (admin).** This index was designed after reading the before plan, which showed a sequential scan of all 119,422 deliveries that discarded 118,282 rows to keep 1,140. Q6 filters on an equality (`tracking_status = 'in_transit'`) and a range (`dispatched_date`), so `idx_deliveries_in_transit` is a partial index: it covers only in-transit rows and is sorted by the range column. Reading `deliveries` became much faster, but the whole query only improved from 27.5 ms to 18.3 ms, for two reasons. First, the 1,140 matching rows are scattered across 703 heap blocks, so the database still has to read 703 separate table pages. Second, the deliveries are joined to orders with a hash join that still reads all 50,000 orders. An index only speeds up the part of the plan it targets, and the rest of this query is now the bottleneck.

## 3. Conclusions

Indexes help most when a query is selective: Q2 (6 of 50,000 rows) improved about 8 times, while Q1 (about 10% of rows) gained far less, and Q5 (about 91%) gained nothing. Having an index does not force PostgreSQL to use it. Its cost-based optimiser estimates the cost of each possible plan from table statistics and picks the cheapest, which is why it ignored the index for Q5 and why a wrong row estimate, as in Q1, can affect the plan it chooses. Indexes can also change the join algorithm, as in Q4, where a hash join became a nested loop with index lookups. Indexes have costs too: each one takes extra storage and has to be updated on every insert, update and delete, so they should be added for real queries, not for every column.

## 4. Method

Both sets of plans use the same data (`sample-data.sql`) and the same queries (`queries.sql`). The before plans were captured with only the indexes PostgreSQL creates automatically for primary keys and UNIQUE constraints. The after plans were captured after running `indexes.sql` and then `ANALYZE`. Each query was run a few times, and timings vary slightly between runs, so small differences such as Q5's are noise rather than improvement.
