# Farmily: Normalisation

This document normalises a sample of Farmily order data from an unnormalised form (UNF) to third normal form (3NF), then checks the result against `schema.sql`.

## 0. Starting point: the unnormalised table (UNF)

| order_no | order_date | customer_name | customer_email | customer_type | delivery_address | region | items (product, farmer, farmer_region, category, harvest_date, expiry_date, qty, unit_price) | payment_ref | payment_method |
|---|---|---|---|---|---|---|---|---|---|
| 1001 | 10/11/2026 | Mama Put Kitchen | mpk@mail.com | restaurant | 12 Allen Ave, Ikeja | Lagos | Ofada rice, Musa Farms, Kano, Grains, 01/11/2026, 01/05/2027, 50, 1800; Yam, Ade Farms, Lagos, Tubers, 05/11/2026, 05/12/2026, 20, 1200 | TX88231 | card |
| 1002 | 10/11/2026 | Bola Ade | bola@mail.com | household | 4 Wuse Rd | Abuja | Ofada rice, Musa Farms, Kano, Grains, 01/11/2026, 01/05/2027, 10, 1800 | TX88240 | mobile_money |

### Anomalies in the original table

- **Update anomaly:** Musa Farms' region is stored once for every order line that includes its rice. If Musa Farms moves out of Kano, both order lines here (one in order 1001, one in order 1002) must be updated, and in real data every line it has ever sold. Missing one leaves the farmer in two regions at once.
- **Insert anomaly:** a new farmer, product or batch cannot be recorded until someone orders it, because every row needs an `order_no`. The same applies to a customer who has registered but not yet ordered.
- **Delete anomaly:** deleting order 1002 removes the only record of Bola Ade's email, customer type and address. Deleting order 1001 removes the only record that Ade Farms exists and that Yam belongs to Tubers.

## 1. UNF → 1NF: remove the repeating group

**What isn't atomic?** The `items` column holds a list: several order lines separated by semicolons, each with eight values separated by commas. A single cell cannot be queried, constrained or indexed by its parts, for example to total the quantity of Ofada rice sold. 1NF requires every cell to hold one value, so the list is split so that each row is one order line, and each item value gets its own column.

**Key:** the sample has no batch ID, so in this data a batch is identified by `product`, `farmer` and `harvest_date` together, because the same farmer can harvest the same product more than once (see design decision A). One row is therefore identified by **(order_no, product, farmer, harvest_date)**, meaning "this batch within this order".

| order_no | order_date | customer_name | customer_email | customer_type | delivery_address | region | product | farmer | farmer_region | category | harvest_date | expiry_date | qty | unit_price | payment_ref | payment_method |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1001 | 10/11/2026 | Mama Put Kitchen | mpk@mail.com | restaurant | 12 Allen Ave, Ikeja | Lagos | Ofada rice | Musa Farms | Kano | Grains | 01/11/2026 | 01/05/2027 | 50 | 1800 | TX88231 | card |
| 1001 | 10/11/2026 | Mama Put Kitchen | mpk@mail.com | restaurant | 12 Allen Ave, Ikeja | Lagos | Yam | Ade Farms | Lagos | Tubers | 05/11/2026 | 05/12/2026 | 20 | 1200 | TX88231 | card |
| 1002 | 10/11/2026 | Bola Ade | bola@mail.com | household | 4 Wuse Rd | Abuja | Ofada rice | Musa Farms | Kano | Grains | 01/11/2026 | 01/05/2027 | 10 | 1800 | TX88240 | mobile_money |

The table is now in 1NF, but the duplication is plain to see: order 1001's customer and payment details appear twice, and Musa Farms' batch details appear twice.

## 2. 1NF → 2NF: remove partial dependencies

A partial dependency is a non-key column that depends on only part of a composite key. Each column was checked against the key (order_no, product, farmer, harvest_date):

| Depends on | Columns | Partial? |
|---|---|---|
| `order_no` only | order_date, customer_name, customer_email, customer_type, delivery_address, region, payment_ref, payment_method | Yes: customer_email is the same whatever batch is on the line (payment_ref and payment_method only hold here because each sample order has one payment; see step 3) |
| the batch only (product, farmer, harvest_date) | farmer_region, category, expiry_date | Yes: the batch's expiry date is the same in every order |
| the whole key | qty, unit_price | No: they describe this batch in this order |

Each group moves into its own table. The batch gets a surrogate key, `listing_id`, as in `schema.sql`, so an order line can refer to it by one column. (product, farmer, harvest_date) identifies each batch in this sample, but it is not a true candidate key: a farmer could list two batches of the same product harvested on the same day with different grades, so `schema.sql` deliberately has no UNIQUE constraint on those three columns.

**orders**

| <u>order_no</u> | order_date | customer_name | customer_email | customer_type | delivery_address | region | payment_ref | payment_method |
|---|---|---|---|---|---|---|---|---|
| 1001 | 10/11/2026 | Mama Put Kitchen | mpk@mail.com | restaurant | 12 Allen Ave, Ikeja | Lagos | TX88231 | card |
| 1002 | 10/11/2026 | Bola Ade | bola@mail.com | household | 4 Wuse Rd | Abuja | TX88240 | mobile_money |

**batches**

| <u>listing_id</u> | product | farmer | farmer_region | category | harvest_date | expiry_date |
|---|---|---|---|---|---|---|
| 1 | Ofada rice | Musa Farms | Kano | Grains | 01/11/2026 | 01/05/2027 |
| 2 | Yam | Ade Farms | Lagos | Tubers | 05/11/2026 | 05/12/2026 |

**order_lines**

| <u>order_no</u> | <u>listing_id</u> | qty | unit_price |
|---|---|---|---|
| 1001 | 1 | 50 | 1800 |
| 1001 | 2 | 20 | 1200 |
| 1002 | 1 | 10 | 1800 |

Musa Farms' batch is now stored once, however many orders include it. `farmer_region` and `category` still depend only on `farmer` and on `product`. With `listing_id` as the key, they show up in the next step as dependencies that pass through another non-key column, and are removed there.

## 3. 2NF → 3NF: remove transitive dependencies

A transitive dependency is a non-key column that depends on another non-key column instead of directly on the key. Five remain:

| Table | Dependency | Problem |
|---|---|---|
| batches | `farmer → farmer_region` | a farmer's region is repeated in every batch they list |
| batches | `product → category` | a product's category is repeated in every batch of it |
| orders | `customer_email → customer_name, customer_type` | customer details are repeated in every order |
| orders | `delivery_address → region` | an address's region is repeated in every order sent there |
| orders | `payment_ref → payment_method` | payment details belong to the payment, not the order, and an order can have several payment attempts |

Each determining column becomes the key of its own table, with a surrogate ID where the natural value is long or could change (an email address, a street address). Region and category names move into lookup tables so that each name is spelled once.

**regions**

| <u>region_id</u> | region_name |
|---|---|
| 1 | Lagos |
| 2 | Abuja |
| 3 | Kano |

**farmers**

| <u>farmer_id</u> | name | region_id |
|---|---|---|
| 1 | Musa Farms | 3 |
| 2 | Ade Farms | 1 |

**categories** and **products**

| <u>category_id</u> | name |
|---|---|
| 1 | Grains |
| 2 | Tubers |

| <u>product_id</u> | product_name | category_id |
|---|---|---|
| 1 | Ofada rice | 1 |
| 2 | Yam | 2 |

**produce_listings** (formerly batches)

| <u>listing_id</u> | farmer_id | product_id | harvest_date | expiry_date |
|---|---|---|---|---|
| 1 | 1 | 1 | 01/11/2026 | 01/05/2027 |
| 2 | 2 | 2 | 05/11/2026 | 05/12/2026 |

**customers** and **addresses**

| <u>customer_id</u> | name | email | customer_type |
|---|---|---|---|
| 1 | Mama Put Kitchen | mpk@mail.com | restaurant |
| 2 | Bola Ade | bola@mail.com | household |

| <u>address_id</u> | customer_id | street / city | region_id |
|---|---|---|---|
| 1 | 1 | 12 Allen Ave, Ikeja | 1 |
| 2 | 2 | 4 Wuse Rd | 2 |

**orders**, **payments** and **order_items**

| <u>order_no</u> | order_date | customer_id | delivery_address_id |
|---|---|---|---|
| 1001 | 10/11/2026 | 1 | 1 |
| 1002 | 10/11/2026 | 2 | 2 |

| <u>payment_ref</u> | order_no | payment_method |
|---|---|---|
| TX88231 | 1001 | card |
| TX88240 | 1002 | mobile_money |

| <u>order_no</u> | <u>listing_id</u> | qty | unit_price_at_purchase |
|---|---|---|---|
| 1001 | 1 | 50 | 1800 |
| 1001 | 2 | 20 | 1200 |
| 1002 | 1 | 10 | 1800 |

Every table is now in 3NF with one deliberate exception. In `orders`, each address belongs to exactly one customer, so `delivery_address_id → customer_id`, which makes `order_no → delivery_address_id → customer_id` a transitive dependency. `customer_id` is kept on the order on purpose: who placed an order is a fact in its own right, it is queried constantly (order history, customer reports), and it should not depend on reaching the customer through an address. The anomaly this kind of dependency normally allows, an order whose customer and delivery address disagree, cannot happen here, because the composite foreign key `(delivery_address_id, customer_id) → addresses (address_id, customer_id)` (constraint 9 in design-decisions.md) forces the address to belong to the order's own customer.

**BCNF:** every table is also in Boyce-Codd normal form, because every determinant is a candidate key (for example `email` in `customers` is UNIQUE). The one exception is `orders`, for the same reason: `delivery_address_id` determines `customer_id` but is not a candidate key of `orders`.

If Musa Farms moves region, one row in `farmers` changes. The three anomalies are gone: a farmer or product can be added before anyone orders it, and deleting an order no longer deletes the customer, farmer or product it mentions.

## 4. Final check against schema.sql

| Normalised table | schema.sql table | Notes |
|---|---|---|
| regions | `regions` | |
| customers | `customers` | schema adds `phone` |
| addresses | `addresses` | schema splits the address into `street` and `city` and adds `delivery_instructions` |
| orders | `orders` | schema adds `order_status`; `order_no` is `order_id` |
| payments | `payments` | schema adds a surrogate `payment_id`; `payment_ref` becomes the UNIQUE `transaction_reference` |
| categories | `categories` | schema adds `parent_category_id` for subcategories |
| products | `products` | schema adds `description` |
| farmers | `farmers` | schema adds `farm_location`, `phone`, `is_verified` |
| produce_listings | `produce_listings` | schema adds `grade`, `unit`, `price_per_unit`, `quantity_available`, `listing_status` |
| order_items | `order_items` | schema adds a surrogate `order_item_id`; the natural key stays as `UNIQUE (order_id, listing_id)` |

Every table produced by normalisation appears in `schema.sql`. The other three schema tables, `riders`, `deliveries` and `reviews`, come from requirements that this sample data does not cover.

**Why order_total isn't stored:** an order's total is always the sum of `qty × unit_price_at_purchase` over its order lines (114,000 for order 1001 and 18,000 for order 1002), so storing it would duplicate data that already exists and would go wrong as soon as a line was added, removed or changed without the total also being updated.

**Why unit_price_at_purchase isn't redundancy:** it records what the customer actually paid on that order line, which is a fact about the sale rather than a copy of the listing's current `price_per_unit`. The listing's price can change tomorrow, but past orders must still show and total the price that applied when they were placed.
