-- =============================================================================
-- Farmily: sample-data.sql (Portfolio 2)
-- Synthetic data for query and index testing. All names, emails, phone numbers
-- and transaction references are made up.
--
-- Run order:  schema.sql  ->  sample-data.sql  ->  (EXPLAIN ANALYZE "before")
--             ->  indexes.sql  ->  (EXPLAIN ANALYZE "after")
--
-- The data is deliberately uneven: a few staple products (rice, yam, tomatoes,
-- garri...) appear in most listings and orders, while others are rare. This
-- makes the selectivity of query conditions differ, which affects the plans the
-- cost-based optimiser chooses.
--
-- setseed() makes random() repeatable, so re-running gives the same data.
-- =============================================================================

SELECT setseed(0.42);

-- -----------------------------------------------------------------------------
-- Regions
-- -----------------------------------------------------------------------------
INSERT INTO regions (region_name) VALUES ('Lagos'), ('Abuja'), ('Kano');

-- -----------------------------------------------------------------------------
-- Categories: 5 top-level categories, then subcategories
-- -----------------------------------------------------------------------------
INSERT INTO categories (name) VALUES
    ('Grains'), ('Tubers'), ('Vegetables'), ('Fruits'), ('Legumes');

INSERT INTO categories (name, parent_category_id)
SELECT sub, (SELECT category_id FROM categories WHERE name = parent AND parent_category_id IS NULL)
FROM (VALUES
    ('Rice', 'Grains'), ('Maize', 'Grains'), ('Millet and Sorghum', 'Grains'),
    ('Yam', 'Tubers'), ('Cassava', 'Tubers'), ('Potatoes', 'Tubers'),
    ('Leafy Vegetables', 'Vegetables'), ('Fruit Vegetables', 'Vegetables'),
    ('Tropical Fruits', 'Fruits'), ('Citrus', 'Fruits'),
    ('Beans', 'Legumes'), ('Groundnuts', 'Legumes')
) AS c(sub, parent);

-- -----------------------------------------------------------------------------
-- Products: 30 products. Listed roughly from most to least popular, because
-- listings below pick products with a skew towards the lower product_ids.
-- base_price (naira per unit) and shelf_days are kept in a temporary table
-- and used to generate realistic listings.
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE product_seed (
    seq         INT,
    name        TEXT,
    category    TEXT,
    unit        TEXT,
    base_price  NUMERIC,
    shelf_days  INT
);

INSERT INTO product_seed VALUES
    ( 1, 'Ofada rice',            'Rice',               'kg',    1800, 270),
    ( 2, 'White yam',             'Yam',                'piece', 2500,  90),
    ( 3, 'Tomatoes',              'Fruit Vegetables',   'crate',25000,   7),
    ( 4, 'Garri (white)',         'Cassava',            'kg',     900, 180),
    ( 5, 'Local parboiled rice',  'Rice',               'kg',    1500, 270),
    ( 6, 'Brown beans (oloyin)',  'Beans',              'kg',    2200, 300),
    ( 7, 'Fresh pepper (tatashe)','Fruit Vegetables',   'kg',    2800,  10),
    ( 8, 'Yellow maize',          'Maize',              'kg',     700, 240),
    ( 9, 'Plantain',              'Tropical Fruits',    'bunch', 4500,  12),
    (10, 'Irish potatoes',        'Potatoes',           'kg',    1600,  60),
    (11, 'Onions',                'Fruit Vegetables',   'kg',    1400,  45),
    (12, 'Garri (yellow)',        'Cassava',            'kg',    1000, 180),
    (13, 'Groundnuts (shelled)',  'Groundnuts',         'kg',    2600, 200),
    (14, 'Ugwu leaves',           'Leafy Vegetables',   'bunch',  500,   4),
    (15, 'Sweet oranges',         'Citrus',             'piece',  150,  21),
    (16, 'Water yam',             'Yam',                'piece', 2000,  60),
    (17, 'Sorghum',               'Millet and Sorghum', 'kg',     800, 300),
    (18, 'Cassava tubers',        'Cassava',            'kg',     400,  14),
    (19, 'Pineapple',             'Tropical Fruits',    'piece', 1200,  10),
    (20, 'Spinach (efo)',         'Leafy Vegetables',   'bunch',  600,   4),
    (21, 'White beans',           'Beans',              'kg',    1900, 300),
    (22, 'Millet',                'Millet and Sorghum', 'kg',     850, 300),
    (23, 'Sweet potatoes',        'Potatoes',           'kg',     900,  45),
    (24, 'Pawpaw',                'Tropical Fruits',    'piece',  900,   8),
    (25, 'Okra',                  'Fruit Vegetables',   'kg',    1500,   7),
    (26, 'Bitter leaf',           'Leafy Vegetables',   'bunch',  700,   6),
    (27, 'Tangerines',            'Citrus',             'piece',  120,  18),
    (28, 'Watermelon',            'Tropical Fruits',    'piece', 3000,  20),
    (29, 'White maize',           'Maize',              'kg',     750, 240),
    (30, 'Bambara nuts',          'Groundnuts',         'kg',    3000, 250);

INSERT INTO products (category_id, product_name, description)
SELECT c.category_id, s.name, s.name || ' sold by Farmily farmers'
FROM product_seed s
JOIN categories c ON c.name = s.category
ORDER BY s.seq;   -- product_id follows seq (1 = most popular)

-- -----------------------------------------------------------------------------
-- Name parts used for farmers, customers and riders
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE first_names (n TEXT[]);
INSERT INTO first_names VALUES (ARRAY[
    'Adebayo','Chinedu','Musa','Ngozi','Aisha','Emeka','Fatima','Tunde','Halima','Ifeanyi',
    'Zainab','Segun','Amina','Uche','Bola','Ibrahim','Kemi','Yusuf','Chioma','Sani',
    'Funke','Abdullahi','Nkechi','Femi','Hauwa','Obinna','Rukayat','Kabiru','Adaeze','Tope']);

CREATE TEMP TABLE last_names (n TEXT[]);
INSERT INTO last_names VALUES (ARRAY[
    'Okafor','Adeyemi','Bello','Eze','Abubakar','Ogunleye','Nwosu','Usman','Balogun','Okeke',
    'Lawal','Obi','Danjuma','Afolabi','Chukwu','Garba','Adewale','Nnamdi','Yakubu','Ojo']);

-- -----------------------------------------------------------------------------
-- Farmers: 500. Kano has the most farmers, Lagos the fewest.
-- About 90% are verified.
-- -----------------------------------------------------------------------------
INSERT INTO farmers (name, farm_location, region_id, phone, is_verified)
SELECT
    (SELECT n[1 + floor(random() * 30)::int] FROM first_names WHERE g > 0) || ' ' ||
    (SELECT n[1 + floor(random() * 20)::int] FROM last_names WHERE g > 0) || ' Farms',
    'Farm plot ' || g,
    CASE WHEN r < 0.45 THEN 3 WHEN r < 0.80 THEN 2 ELSE 1 END,   -- Kano, Abuja, Lagos
    '080' || lpad((10000000 + g)::text, 8, '0'),
    random() < 0.90
FROM (SELECT g, random() AS r FROM generate_series(1, 500) AS g) AS s;

-- -----------------------------------------------------------------------------
-- Customers: 5,000. Mostly households, then restaurants, then retailers.
-- -----------------------------------------------------------------------------
INSERT INTO customers (name, customer_type, phone, email)
SELECT
    CASE WHEN r < 0.70
         THEN (SELECT n[1 + floor(random() * 30)::int] FROM first_names WHERE g > 0) || ' ' ||
              (SELECT n[1 + floor(random() * 20)::int] FROM last_names WHERE g > 0)
         WHEN r < 0.90
         THEN (SELECT n[1 + floor(random() * 30)::int] FROM first_names WHERE g > 0) || '''s Kitchen ' || g
         ELSE 'Mini Mart ' || g
    END,
    CASE WHEN r < 0.70 THEN 'household' WHEN r < 0.90 THEN 'restaurant' ELSE 'retailer' END,
    '081' || lpad((20000000 + g)::text, 8, '0'),
    'customer' || g || '@example.com'
FROM (SELECT g, random() AS r FROM generate_series(1, 5000) AS g) AS s;

-- -----------------------------------------------------------------------------
-- Addresses: every customer gets one address; about 40% get a second one.
-- Lagos has the most buyers.
-- -----------------------------------------------------------------------------
INSERT INTO addresses (customer_id, street, city, region_id, delivery_instructions)
SELECT
    c.customer_id,
    (1 + floor(random() * 200)::int) || ' ' ||
        (ARRAY['Allen Avenue','Wuse Road','Zaria Road','Admiralty Way','Ahmadu Bello Way',
               'Bompai Road','Herbert Macaulay Way','Gimbiya Street'])[1 + floor(random() * 8)::int],
    CASE region WHEN 1 THEN 'Ikeja' WHEN 2 THEN 'Garki' ELSE 'Nassarawa' END,
    region,
    CASE WHEN random() < 0.3 THEN 'Call on arrival' END
FROM customers c
CROSS JOIN LATERAL generate_series(1, CASE WHEN random() + 0 * c.customer_id < 0.40 THEN 2 ELSE 1 END) AS a(n)
CROSS JOIN LATERAL (SELECT CASE WHEN random() + 0 * c.customer_id + 0 * a.n < 0.50 THEN 1
                                WHEN random() < 0.60 THEN 2 ELSE 3 END AS region) AS rg;

-- -----------------------------------------------------------------------------
-- Riders: 150, spread across the three regions.
-- -----------------------------------------------------------------------------
INSERT INTO riders (name, phone, region_id, availability_status)
SELECT
    (SELECT n[1 + floor(random() * 30)::int] FROM first_names WHERE g > 0) || ' ' ||
    (SELECT n[1 + floor(random() * 20)::int] FROM last_names WHERE g > 0),
    '090' || lpad((30000000 + g)::text, 8, '0'),
    1 + (g % 3),
    (ARRAY['available','busy','offline'])[1 + floor(random() * 3)::int]
FROM generate_series(1, 150) AS g;

-- -----------------------------------------------------------------------------
-- Produce listings: 20,000 batches harvested between Nov 2025 and Nov 2026.
-- product_id = 1 + floor(30 * random()^2) skews towards popular products.
-- Expiry = harvest + the product's shelf life. Listings past expiry are marked
-- 'expired'; most current ones are 'active'.
-- -----------------------------------------------------------------------------
INSERT INTO produce_listings (farmer_id, product_id, harvest_date, expiry_date, grade,
                              unit, price_per_unit, quantity_available, listing_status)
SELECT
    farmer_id,
    p.seq,
    harvest,
    harvest + p.shelf_days,
    grade,
    p.unit,
    round(p.base_price * CASE grade WHEN 'A' THEN 1.15 WHEN 'B' THEN 1.0 ELSE 0.85 END
                       * (0.9 + random() * 0.2)::numeric, 2),
    CASE WHEN status = 'sold_out' THEN 0 ELSE round((5 + random() * 495)::numeric, 2) END,
    status
FROM (
    SELECT
        1 + floor(random() * 500)::int                      AS farmer_id,
        1 + floor(30 * power(random(), 2))::int             AS product_seq,
        DATE '2025-11-10' + floor(random() * 366)::int      AS harvest,
        CASE WHEN random() < 0.55 THEN 'A' WHEN random() < 0.7 THEN 'B' ELSE 'C' END AS grade,
        random()                                            AS r
    FROM generate_series(1, 20000)
) AS x
JOIN product_seed p ON p.seq = x.product_seq
CROSS JOIN LATERAL (
    SELECT CASE
        WHEN x.harvest + p.shelf_days < DATE '2026-11-10' THEN 'expired'
        WHEN x.r < 0.80 THEN 'active'
        WHEN x.r < 0.95 THEN 'sold_out'
        ELSE 'withdrawn'
    END AS status
) AS st;

-- -----------------------------------------------------------------------------
-- Orders: 50,000 over the last 12 months. Each order picks a random address,
-- and the order's customer is that address's owner, which keeps the composite
-- foreign key (delivery_address_id, customer_id) valid.
-- -----------------------------------------------------------------------------
INSERT INTO orders (customer_id, order_date, order_status, delivery_address_id)
SELECT
    a.customer_id,
    TIMESTAMPTZ '2025-11-10 08:00+01' + random() * INTERVAL '365 days',
    CASE WHEN r < 0.70 THEN 'delivered'
         WHEN r < 0.80 THEN 'dispatched'
         WHEN r < 0.88 THEN 'paid'
         WHEN r < 0.95 THEN 'pending'
         ELSE 'cancelled' END,
    a.address_id
FROM (
    SELECT 1 + floor(random() * (SELECT max(address_id) FROM addresses))::int AS addr,
           random() AS r
    FROM generate_series(1, 50000)
) AS o
JOIN addresses a ON a.address_id = o.addr;

-- -----------------------------------------------------------------------------
-- Order items: 1 to 5 lines per order (about 150,000 in total). Listings are
-- picked with the same popularity skew. A listing can appear only once per
-- order, so duplicate picks are skipped by ON CONFLICT.
-- unit_price_at_purchase copies the listing's price at the time of the order.
-- -----------------------------------------------------------------------------
INSERT INTO order_items (order_id, listing_id, quantity, unit_price_at_purchase)
SELECT o.order_id, l.listing_id, round((1 + random() * 49)::numeric, 2), l.price_per_unit
FROM orders o
CROSS JOIN LATERAL generate_series(1, 1 + floor(random() * 5 + 0 * o.order_id)::int) AS line(n)
CROSS JOIN LATERAL (
    SELECT 1 + floor(20000 * power(random() + 0 * o.order_id + 0 * line.n, 1.6))::int AS pick
) AS pk
JOIN produce_listings l ON l.listing_id = pk.pick
ON CONFLICT (order_id, listing_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Payments. Every non-pending order gets one payment for its full total.
-- About 5% of orders also have an earlier failed attempt.
-- Cancelled orders are refunded. Cash on delivery has no transaction reference.
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE order_totals AS
SELECT order_id, sum(quantity * unit_price_at_purchase) AS total
FROM order_items
GROUP BY order_id;

-- Earlier failed attempts
INSERT INTO payments (order_id, amount, payment_method, payment_status, transaction_reference)
SELECT o.order_id, t.total, 'card', 'failed', 'TXF' || o.order_id
FROM orders o
JOIN order_totals t ON t.order_id = o.order_id
WHERE o.order_status <> 'pending' AND random() < 0.05;

-- Final payment for each order
INSERT INTO payments (order_id, amount, payment_method, payment_status, transaction_reference)
SELECT
    o.order_id,
    t.total,
    m.method,
    CASE WHEN o.order_status = 'cancelled' THEN 'refunded' ELSE 'completed' END,
    CASE WHEN m.method = 'cash_on_delivery' THEN NULL ELSE 'TX' || o.order_id END
FROM orders o
JOIN order_totals t ON t.order_id = o.order_id
CROSS JOIN LATERAL (
    SELECT CASE WHEN r < 0.40 THEN 'card' WHEN r < 0.70 THEN 'bank_transfer'
                WHEN r < 0.90 THEN 'mobile_money' ELSE 'cash_on_delivery' END AS method
    FROM (SELECT random() + 0 * o.order_id AS r) AS z
) AS m
WHERE o.order_status <> 'pending';

-- -----------------------------------------------------------------------------
-- Deliveries: one per (order, farmer) for dispatched and delivered orders.
-- Dispatched one day after ordering, delivered one to three days later.
-- -----------------------------------------------------------------------------
INSERT INTO deliveries (order_id, farmer_id, rider_id, tracking_status, dispatched_date, delivered_date)
SELECT
    d.order_id,
    d.farmer_id,
    1 + floor(random() * 150)::int,
    CASE WHEN d.order_status = 'delivered' THEN 'delivered' ELSE 'in_transit' END,
    d.order_date + INTERVAL '1 day',
    CASE WHEN d.order_status = 'delivered'
         THEN d.order_date + INTERVAL '1 day' + (1 + floor(random() * 3)::int) * INTERVAL '1 day'
    END
FROM (
    SELECT DISTINCT o.order_id, o.order_status, o.order_date, l.farmer_id
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN produce_listings l ON l.listing_id = oi.listing_id
    WHERE o.order_status IN ('dispatched', 'delivered')
) AS d;

-- -----------------------------------------------------------------------------
-- Reviews: about 20% of delivered parcels get a review of the farmer,
-- naming one of the listings that was in the parcel. Ratings lean positive.
-- -----------------------------------------------------------------------------
INSERT INTO reviews (customer_id, farmer_id, listing_id, rating, comment, review_date)
SELECT
    o.customer_id,
    d.farmer_id,
    (SELECT min(oi.listing_id)
     FROM order_items oi
     JOIN produce_listings l ON l.listing_id = oi.listing_id
     WHERE oi.order_id = d.order_id AND l.farmer_id = d.farmer_id),
    CASE WHEN r < 0.45 THEN 5 WHEN r < 0.75 THEN 4 WHEN r < 0.88 THEN 3
         WHEN r < 0.95 THEN 2 ELSE 1 END,
    CASE WHEN r < 0.75 THEN 'Fresh produce and quick delivery'
         WHEN r < 0.88 THEN 'Okay, but packaging could be better'
         ELSE 'Produce was not as described' END,
    d.delivered_date + INTERVAL '1 day'
FROM deliveries d
JOIN orders o ON o.order_id = d.order_id
CROSS JOIN LATERAL (SELECT random() + 0 * d.delivery_id AS r) AS z
WHERE d.tracking_status = 'delivered' AND random() < 0.20;

-- -----------------------------------------------------------------------------
-- Refresh the planner's statistics so EXPLAIN uses the real table sizes.
-- -----------------------------------------------------------------------------
ANALYZE;

-- Row counts (report these in the Portfolio 2 README)
SELECT 'regions' AS table_name, count(*) AS row_count FROM regions
UNION ALL SELECT 'categories',       count(*) FROM categories
UNION ALL SELECT 'products',         count(*) FROM products
UNION ALL SELECT 'farmers',          count(*) FROM farmers
UNION ALL SELECT 'customers',        count(*) FROM customers
UNION ALL SELECT 'addresses',        count(*) FROM addresses
UNION ALL SELECT 'riders',           count(*) FROM riders
UNION ALL SELECT 'produce_listings', count(*) FROM produce_listings
UNION ALL SELECT 'orders',           count(*) FROM orders
UNION ALL SELECT 'order_items',      count(*) FROM order_items
UNION ALL SELECT 'payments',         count(*) FROM payments
UNION ALL SELECT 'deliveries',       count(*) FROM deliveries
UNION ALL SELECT 'reviews',          count(*) FROM reviews;
