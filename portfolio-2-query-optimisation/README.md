# Portfolio 2: Query Processing and Optimisation

## What I did

I loaded the Farmily database from Portfolio 1 with a realistic volume of synthetic data and wrote six everyday queries, two each for a buyer, a farmer and an admin. I captured each query's execution plan with `EXPLAIN ANALYZE` before and after adding indexes, and analysed when and why the indexes changed the plan, in `analysis.md`.

## Files

- `sample-data.sql`: generates the synthetic data (500 farmers, 5,000 customers, 20,000 listings, 50,000 orders and related rows).
- `row-counts.png`: the row count of each table after loading the data.
- `queries.sql`: the six queries (Q1 to Q6), each with a comment saying who uses it and what it answers.
- `indexes.sql`: the indexes added for the after plans, 19 in total.
- `plans/before/`: `EXPLAIN ANALYZE` output for each query with no extra indexes (`q1.txt` to `q6.txt`).
- `plans/after/`: `EXPLAIN ANALYZE` output for each query after running `indexes.sql`.
- `analysis.md`: the before and after comparison, an explanation for each query, and conclusions.

## How I implemented it

**Order of work:**

1. Created the tables with `schema.sql` from Portfolio 1, in PostgreSQL 16 running in Docker, using DBeaver.
2. Ran `sample-data.sql` and checked the row counts.
3. Ran each query in `queries.sql` with `EXPLAIN ANALYZE` and saved the output to `plans/before/`.
4. Ran `indexes.sql`, then `ANALYZE` to refresh the planner's statistics.
5. Ran the same queries again and saved the output to `plans/after/`.
6. Compared the two sets of plans in `analysis.md`.

**Why the data is this size:** with only a few rows, a table fits in a handful of disk pages, and reading all of it is cheaper than using an index, so PostgreSQL chooses a sequential scan whatever indexes exist. The tables therefore had to be large enough for indexes to make a measurable difference. The data is also deliberately uneven: a few staple products, such as Ofada rice, appear in most listings, so some conditions match many rows and others very few. This gives the optimiser real choices to make.

**Row counts** (`row-counts.png`):

| Table | Rows |
|---|---|
| order_items | 150,085 |
| deliveries | 119,422 |
| orders | 50,000 |
| payments | 48,848 |
| reviews | 20,793 |
| produce_listings | 20,000 |
| addresses | 6,960 |
| customers | 5,000 |
| farmers | 500 |
| riders | 150 |
| products | 30 |
| categories | 17 |
| regions | 3 |

**Synthetic and reproducible:** all names, emails, phone numbers and transaction references are made up. The script starts with `setseed(0.42)`, which makes PostgreSQL's `random()` return the same sequence every time, so re-running it produces exactly the same data. The queries use a fixed "today" of 2026-11-10, so their results and plans can be reproduced too. `sample-data.sql` was generated with AI assistance (Claude) and checked by running it and confirming the row counts above.

**The Q6 index:** most of `indexes.sql` covers foreign keys and the buyer's product search. `idx_deliveries_in_transit` was added after reading Q6's before plan, which showed a sequential scan of all 119,422 deliveries to find about 1,140. It is a partial index on `dispatched_date` that only covers in-transit deliveries.

## How I tested it

- **Data:** checked that every table had the expected number of rows (`row-counts.png`).
- **Queries:** checked that each query returns sensible results, for example 6 orders for customer 42 (Q2), 4 expiring listings for farmer 5 (Q3) and 10 farmers for the top-rated list (Q5).
- **Indexes:** confirmed that `indexes.sql` created all 19 indexes.
- **Plans:** ran each query with `EXPLAIN ANALYZE` a few times before saving the plan, because timings vary slightly between runs. A difference of a millisecond or so, such as Q5's, is treated as noise.

## Notes

- Q5 shows that an index is not always used: the query needs about 91% of the reviews, so PostgreSQL correctly keeps the sequential scan. `analysis.md` suggests a materialised view as the better fix and explains its trade-off.
- The before plans still use the indexes PostgreSQL creates automatically for primary keys and UNIQUE constraints, which is why Q2's order_items lookup and Q3 were already fairly fast.
