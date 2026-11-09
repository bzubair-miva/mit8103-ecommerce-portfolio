-- =============================================================================
-- Farmily: farm-to-customer produce marketplace
-- schema.sql: relational schema (PostgreSQL 16)
--
-- Implements the conceptual ERD in farmily-erd.png. Design notes:
--   * The M:N CONTAINS relationship (Order <-> ProduceListing) is resolved into
--     the order_items table; its relationship attributes (quantity,
--     unit_price_at_purchase) become columns.
--   * Derived attributes in the ERD (Order.order_total, Farmer.average_rating)
--     are NOT stored; they are calculated in queries to avoid update anomalies.
--   * unit_price_at_purchase is a deliberate historical snapshot, not
--     redundancy: listing prices change, past order lines must not.
--   * Composite foreign keys enforce cross-table rules that a single-column FK
--     cannot (an order ships to one of its own customer's addresses; a review's
--     listing belongs to the farmer being reviewed).
-- Indexes are created separately in portfolio-2-query-optimisation/indexes.sql
-- so that query performance can be compared before and after indexing.
-- Full rationale: design-decisions.md
-- =============================================================================

-- Re-runnable: drop in reverse dependency order.
DROP TABLE IF EXISTS reviews, deliveries, riders, payments, order_items, orders,
                     produce_listings, products, addresses, farmers, categories,
                     customers, regions CASCADE;

-- -----------------------------------------------------------------------------
-- Reference / location
-- -----------------------------------------------------------------------------
CREATE TABLE regions (
    region_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    region_name  VARCHAR(100) NOT NULL UNIQUE
);

-- -----------------------------------------------------------------------------
-- People
-- -----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           VARCHAR(120) NOT NULL,
    customer_type  VARCHAR(20)  NOT NULL
                   CHECK (customer_type IN ('household', 'restaurant', 'retailer')),
    phone          VARCHAR(20)  NOT NULL,
    email          VARCHAR(254) NOT NULL UNIQUE
                   CHECK (email LIKE '%_@_%._%')
);

CREATE TABLE farmers (
    farmer_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           VARCHAR(120) NOT NULL,
    farm_location  VARCHAR(200),
    region_id      INT          NOT NULL
                   REFERENCES regions (region_id) ON DELETE RESTRICT,
    phone          VARCHAR(20)  NOT NULL,
    is_verified    BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE TABLE riders (
    rider_id             INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                 VARCHAR(120) NOT NULL,
    phone                VARCHAR(20)  NOT NULL,
    region_id            INT          NOT NULL
                         REFERENCES regions (region_id) ON DELETE RESTRICT,
    availability_status  VARCHAR(20)  NOT NULL DEFAULT 'offline'
                         CHECK (availability_status IN ('available', 'busy', 'offline'))
);

CREATE TABLE addresses (
    address_id             INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id            INT          NOT NULL
                           REFERENCES customers (customer_id) ON DELETE CASCADE,
    street                 VARCHAR(200) NOT NULL,
    city                   VARCHAR(100) NOT NULL,
    region_id              INT          NOT NULL
                           REFERENCES regions (region_id) ON DELETE RESTRICT,
    delivery_instructions  VARCHAR(500),
    -- Target for the composite FK in orders (address must belong to the customer).
    UNIQUE (address_id, customer_id)
);

-- -----------------------------------------------------------------------------
-- Catalogue
-- -----------------------------------------------------------------------------
CREATE TABLE categories (
    category_id         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    parent_category_id  INT          -- NULL = top-level category
                        REFERENCES categories (category_id) ON DELETE RESTRICT,
    CHECK (parent_category_id IS NULL OR parent_category_id <> category_id),
    -- No duplicate names under the same parent (incl. two top-level duplicates).
    UNIQUE NULLS NOT DISTINCT (parent_category_id, name)
);

CREATE TABLE products (
    product_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id   INT          NOT NULL
                  REFERENCES categories (category_id) ON DELETE RESTRICT,
    product_name  VARCHAR(120) NOT NULL,
    description   TEXT,
    UNIQUE (product_name, category_id)
);

-- One row = one harvested batch a farmer is selling.
CREATE TABLE produce_listings (
    listing_id          INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    farmer_id           INT           NOT NULL
                        REFERENCES farmers (farmer_id) ON DELETE RESTRICT,
    product_id          INT           NOT NULL
                        REFERENCES products (product_id) ON DELETE RESTRICT,
    harvest_date        DATE          NOT NULL,
    expiry_date         DATE          NOT NULL,
    grade               CHAR(1)       NOT NULL DEFAULT 'A'
                        CHECK (grade IN ('A', 'B', 'C')),
    unit                VARCHAR(10)   NOT NULL
                        CHECK (unit IN ('kg', 'g', 'litre', 'piece', 'bunch', 'crate')),
    price_per_unit      NUMERIC(10,2) NOT NULL CHECK (price_per_unit > 0),
    quantity_available  NUMERIC(10,2) NOT NULL CHECK (quantity_available >= 0),
    listing_status      VARCHAR(20)   NOT NULL DEFAULT 'active'
                        CHECK (listing_status IN ('active', 'sold_out', 'expired', 'withdrawn')),
    CHECK (expiry_date > harvest_date),
    -- Target for the composite FK in reviews (listing must belong to the farmer).
    UNIQUE (listing_id, farmer_id)
);

-- -----------------------------------------------------------------------------
-- Transactions
-- -----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id             INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id          INT         NOT NULL
                         REFERENCES customers (customer_id) ON DELETE RESTRICT,
    order_date           TIMESTAMPTZ NOT NULL DEFAULT now(),
    order_status         VARCHAR(20) NOT NULL DEFAULT 'pending'
                         CHECK (order_status IN ('pending', 'paid', 'dispatched',
                                                 'delivered', 'cancelled')),
    delivery_address_id  INT         NOT NULL,
    -- SHIPS_TO: the address must be one of this customer's own addresses.
    FOREIGN KEY (delivery_address_id, customer_id)
        REFERENCES addresses (address_id, customer_id) ON DELETE RESTRICT
);

-- Resolves the M:N CONTAINS relationship between orders and produce_listings.
CREATE TABLE order_items (
    order_item_id           INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id                INT           NOT NULL
                            REFERENCES orders (order_id) ON DELETE CASCADE,
    listing_id              INT           NOT NULL
                            REFERENCES produce_listings (listing_id) ON DELETE RESTRICT,
    quantity                NUMERIC(10,2) NOT NULL CHECK (quantity > 0),
    unit_price_at_purchase  NUMERIC(10,2) NOT NULL CHECK (unit_price_at_purchase >= 0),
    UNIQUE (order_id, listing_id)          -- one line per listing per order
);

CREATE TABLE payments (
    payment_id             INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id               INT           NOT NULL
                           REFERENCES orders (order_id) ON DELETE RESTRICT,
    amount                 NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    payment_method         VARCHAR(20)   NOT NULL
                           CHECK (payment_method IN ('card', 'mobile_money',
                                                     'bank_transfer', 'cash_on_delivery')),
    payment_status         VARCHAR(20)   NOT NULL DEFAULT 'pending'
                           CHECK (payment_status IN ('pending', 'completed', 'failed', 'refunded')),
    transaction_reference  VARCHAR(100)  UNIQUE,   -- NULL allowed, e.g. cash on delivery
    CHECK (payment_status <> 'completed' OR payment_method = 'cash_on_delivery'
           OR transaction_reference IS NOT NULL)
);

-- One delivery per (order, farmer): a multi-farmer order ships as several parcels.
CREATE TABLE deliveries (
    delivery_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id         INT         NOT NULL
                     REFERENCES orders (order_id) ON DELETE CASCADE,
    farmer_id        INT         NOT NULL
                     REFERENCES farmers (farmer_id) ON DELETE RESTRICT,
    rider_id         INT         -- NULL until a rider is assigned
                     REFERENCES riders (rider_id) ON DELETE SET NULL,
    tracking_status  VARCHAR(20) NOT NULL DEFAULT 'pending'
                     CHECK (tracking_status IN ('pending', 'assigned', 'in_transit',
                                                'delivered', 'failed')),
    dispatched_date  TIMESTAMPTZ,
    delivered_date   TIMESTAMPTZ,
    UNIQUE (order_id, farmer_id),
    CHECK (tracking_status NOT IN ('assigned', 'in_transit', 'delivered')
           OR rider_id IS NOT NULL),
    CHECK (tracking_status <> 'delivered' OR delivered_date IS NOT NULL),
    CHECK (delivered_date IS NULL
           OR (dispatched_date IS NOT NULL AND delivered_date >= dispatched_date))
);

CREATE TABLE reviews (
    review_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  INT         NOT NULL
                 REFERENCES customers (customer_id) ON DELETE CASCADE,
    farmer_id    INT         NOT NULL
                 REFERENCES farmers (farmer_id) ON DELETE CASCADE,
    listing_id   INT,        -- optional: review may be about the farmer in general
    rating       SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment      TEXT,
    review_date  TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- ABOUT: if a listing is given, it must be one of this farmer's listings.
    -- If the listing is deleted, keep the review but clear only listing_id.
    FOREIGN KEY (listing_id, farmer_id)
        REFERENCES produce_listings (listing_id, farmer_id)
        ON DELETE SET NULL (listing_id)
);
