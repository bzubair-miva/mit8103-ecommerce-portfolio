-- =============================================================================
-- Farmily: indexes.sql (Portfolio 2)
-- Run AFTER schema.sql and the sample data, and after capturing the
-- 'before' EXPLAIN ANALYZE output, so the effect of each index can be measured.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Indexes on foreign keys since PostgreSQL does not create it automatically
-- -----------------------------------------------------------------------------
CREATE INDEX idx_farmers_region           ON farmers (region_id);
CREATE INDEX idx_riders_region            ON riders (region_id);
CREATE INDEX idx_addresses_customer       ON addresses (customer_id);
CREATE INDEX idx_addresses_region         ON addresses (region_id);
CREATE INDEX idx_categories_parent        ON categories (parent_category_id);
CREATE INDEX idx_products_category        ON products (category_id);
CREATE INDEX idx_listings_farmer          ON produce_listings (farmer_id);
CREATE INDEX idx_listings_product         ON produce_listings (product_id);
CREATE INDEX idx_orders_customer          ON orders (customer_id);
CREATE INDEX idx_orders_address           ON orders (delivery_address_id);
CREATE INDEX idx_order_items_listing      ON order_items (listing_id);
CREATE INDEX idx_payments_order           ON payments (order_id);
CREATE INDEX idx_deliveries_farmer        ON deliveries (farmer_id);
CREATE INDEX idx_deliveries_rider         ON deliveries (rider_id);
CREATE INDEX idx_reviews_customer         ON reviews (customer_id);
CREATE INDEX idx_reviews_farmer           ON reviews (farmer_id);
CREATE INDEX idx_reviews_listing          ON reviews (listing_id);

-- Shopping query: active, unexpired stock for a product.
CREATE INDEX idx_listings_active ON produce_listings (product_id, expiry_date)
    WHERE listing_status = 'active';

-- Delivery tracking: parcels still in transit, by dispatch date.
CREATE INDEX idx_deliveries_in_transit ON deliveries (dispatched_date)
    WHERE tracking_status = 'in_transit';
