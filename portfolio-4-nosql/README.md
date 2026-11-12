# Portfolio 4: NoSQL and Advanced Data Models

## What I did

I modelled the Farmily case study as a MongoDB document database with five collections, choosing for each relationship whether to embed or reference it. I ran buyer, farmer and admin queries against it, tested schema validation, a conditional stock update and index use, and compared the model with the PostgreSQL design from Portfolios 1 to 3 in `suitability.md`.

## Files

- `farmily-mongo.js`: one script that builds the database (collections, schema validation, sample data, indexes) and then runs the queries and tests.
- `mongo1-database-built.png`: documents per collection, and Q1 (active Ofada rice, cheapest first, with the farmer embedded).
- `mongo2-attribute-search.png`: Q2a and Q2b, searches on product-specific attributes.
- `mongo3-orders-and-sales.png`: Q3 (a customer's order history with totals) and Q4 (a farmer's sales per product).
- `mongo4a-ratings.png`: Q5 (farmers by stored rating), then a new review added and the stored rating checked against the reviews collection.
- `mongo4b-stock-update.png`: the conditional stock update, with two buyers each trying to buy the last 50 kg.
- `mongo5-validation-and-explain.png`: two inserts rejected by schema validation, and Q1's plan with and without its index.
- `suitability.md`: the data model, why it suits Farmily, its trade-offs against PostgreSQL, and my verdict.

## How I implemented it

- **Database:** MongoDB running in a Docker container, `farmily-mongo`, alongside the PostgreSQL container from the earlier portfolios.
- **One script:** everything is in `farmily-mongo.js`, run with `mongosh` inside the container from the `portfolio-4-nosql` folder:

```
docker cp farmily-mongo.js farmily-mongo:/tmp/farmily-mongo.js
docker exec -it farmily-mongo mongosh --quiet /tmp/farmily-mongo.js
```

  The script drops and rebuilds the `farmily` database each time, so it can be run again safely and always gives the same output.
- **Model:** five collections (`farmers`, `customers`, `listings`, `orders`, `reviews`). Data that is read together and stays small is embedded: order items, payments and deliveries in orders, addresses in customers, and a copy of the farmer's name and region in each listing. Reviews are referenced by `farmer_id`, because they grow without limit and a document cannot exceed 16 MB. The reasons are explained in `suitability.md`.
- **Data:** a small hand-made sample (5 farmers, 4 customers, 12 listings, 6 orders, 8 reviews) that reuses names and IDs from the PostgreSQL data, such as listing 3 and customer 42, so results can be compared. The listings deliberately cover very different produce, so that their `attributes` differ.
- **Rules and indexes:** `$jsonSchema` validators on `listings` and `orders` check required fields, allowed values and ranges (price above 0, stock not negative, at least one order item). Five indexes support the queries, including a compound index for Q1 and a multikey index on `items.farmer_id` for Q4.

## How I tested it

| Test | Expected result | Actual result |
|---|---|---|
| Build | 5 / 4 / 12 / 6 / 8 documents | 5 farmers, 4 customers, 12 listings, 6 orders, 8 reviews (`mongo1`) |
| Q1 | Active, unexpired Ofada rice, cheapest first, with farmer details | Listings 3 (1843.29, Musa Bello Farms) and 22 (1969.7, Ngozi Okafor Farms) |
| Q2a / Q2b | Only listings matching product-specific attributes | Q2a: listing 40 (firm, 25 kg crates); Q2b: listing 22 (destoned, 11.8% moisture) (`mongo2`) |
| Q3 | Customer 42's orders, newest first, totals calculated from items | 50025 (23,750), 50010 (111,500), 50002 (85,865.80) (`mongo3`) |
| Q4 | Farmer 416's sales, cancelled orders excluded | Ofada rice 20 kg / 36,865.80; fresh pepper 10 kg / 27,500 (`mongo3`) |
| Q5 and new review | Stored rating updated and equal to the value calculated from reviews | Farmer 5: 3 reviews, average 3, in both (`mongo4a`) |
| Conditional stock update | Buyer A succeeds; Buyer B changes nothing | A: matched 1, modified 1; B: matched 0, modified 0; stock 0 (`mongo4b`) |
| Schema validation | Negative stock and an empty order rejected | Both "Document failed validation" (`mongo5`) |
| Index use | Q1 uses its index | `FETCH <- IXSCAN`, 2 documents examined; 12 with the index disabled (`mongo5`) |

Every test produced the expected result.

## Notes

- The conditional stock update was run as two updates one after the other in one script, not from two simultaneous sessions as in Portfolio 3. The result still holds under real concurrency, because the check and the change are a single atomic operation on one document.
- The order and the stock live in different documents, so they cannot be updated in one transaction on this single-server setup. Multi-document transactions need a replica set, which is set up in Portfolio 5.
