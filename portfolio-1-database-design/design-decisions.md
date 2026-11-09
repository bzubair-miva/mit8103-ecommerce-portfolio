# Farmily: Entity List and Design Decisions

## 1. Proposed entities

The database design uses the following entities to represent Farmily's main users, products, transactions and delivery operations. Table names are plural and in lower case. `ORDER` is a reserved word in SQL, so the order table is called `orders`.

| Table | Main attributes |
|---|---|
| regions | region_id (PK), region_name (UNIQUE) |
| farmers | farmer_id (PK), name, farm_location, region_id (FK), phone, is_verified (BOOLEAN) |
| customers | customer_id (PK), name, customer_type, phone, email (UNIQUE) |
| addresses | address_id (PK), customer_id (FK), street, city, region_id (FK), delivery_instructions |
| categories | category_id (PK), name, parent_category_id (FK, NULL for top-level categories) |
| products | product_id (PK), category_id (FK), product_name, description; UNIQUE (product_name, category_id) |
| produce_listings (batch) | listing_id (PK), farmer_id (FK), product_id (FK), harvest_date, expiry_date, grade, unit, price_per_unit, quantity_available, listing_status |
| orders | order_id (PK), customer_id (FK), order_date, order_status, delivery_address_id (FK) |
| order_items | order_item_id (PK), order_id (FK), listing_id (FK), quantity, unit_price_at_purchase |
| payments | payment_id (PK), order_id (FK), amount, payment_method, payment_status, transaction_reference (UNIQUE) |
| riders | rider_id (PK), name, phone, region_id (FK), availability_status |
| deliveries | delivery_id (PK), order_id (FK), farmer_id (FK), rider_id (FK), tracking_status, dispatched_date, delivered_date; UNIQUE (order_id, farmer_id) |
| reviews | review_id (PK), customer_id (FK), farmer_id (FK), listing_id (FK, optional), rating, comment, review_date |

The categories table supports hierarchical categories. For example, Grains can have Rice as a subcategory, while Tubers can have Yam as a subcategory. Top-level categories have no parent, so `parent_category_id` allows NULL.

The regions table (Lagos, Abuja, Kano) is referenced by farmers, addresses and riders instead of storing the region as free text. This avoids inconsistent values such as "Lagos" and "lagos", and it also gives a natural key for splitting data by region in the distributed design (Portfolio 5).

A payment belongs to one order, but an order can have more than one payment record. For example, a failed payment attempt can be followed by a successful one.

## 2. Design decisions

### A. Why separate Product from Batch?

Product and Batch represent two different things. Product describes the general agricultural item, such as Ofada rice, while Batch represents a particular quantity of that product supplied by a specific farmer. Two farmers can sell the same product but have different prices, harvest dates, grades and quantities. Similarly, one farmer can harvest the same product several times, creating different batches. Separating them avoids duplication and allows the system to track the quality, availability and expiry of each batch independently.

### B. How should deliveries work when an order contains products from several farmers?

The system should support multiple deliveries per order. A customer may purchase rice from one farmer and yam from another farmer in a single order. Since the farmers may operate in different locations, their products may require separate collection and delivery arrangements. Therefore, each farmer's portion of an order can have its own delivery record, rider, tracking status and delivery dates. This also allows the customer to track different parts of the same order independently.

The items in each delivery are found through the listing's farmer: an order item belongs to the delivery whose `farmer_id` matches the farmer of its listing. `UNIQUE (order_id, farmer_id)` on deliveries makes sure there is only one delivery per farmer for each order.

### C. What domain constraints should the database enforce?

The following constraints help maintain data accuracy and prevent invalid transactions. They fall into two groups, depending on how the database can enforce them.

**Enforced within the table definition (CHECK, NOT NULL, UNIQUE, FOREIGN KEY):**

1. Expiry date: the expiry date must be later than the harvest date (`CHECK (expiry_date > harvest_date)`).
2. Available quantity: quantity available must never be negative (`CHECK (quantity_available >= 0)`).
3. Price: the price per unit must be greater than zero (`CHECK (price_per_unit > 0)`).
4. Order quantity: each order item must have a quantity greater than zero (`CHECK (quantity > 0)`).
5. Delivery dates: a delivery cannot be marked as delivered before it has been dispatched (`CHECK (delivered_date IS NULL OR (dispatched_date IS NOT NULL AND delivered_date >= dispatched_date))`). The longer form is needed because a CHECK treats a NULL comparison as passing, so a simple `delivered_date >= dispatched_date` would allow a delivered date with no dispatch date.
6. Rating: a review rating must be between 1 and 5 (`CHECK (rating BETWEEN 1 AND 5)`).
7. Status values: status columns only accept fixed values, for example `order_status IN ('pending', 'paid', 'dispatched', 'delivered', 'cancelled')`. The same applies to listing, payment and tracking status.
8. Uniqueness: customer email, payment transaction reference, product name within a category, and one delivery per farmer per order.

**Involving more than one table (enforced with triggers or transaction logic):**

9. Listing expiry: expired produce listings cannot be used for new purchases. This needs the listing's expiry date to be checked when an order item is inserted.
10. Stock availability: an order quantity cannot exceed the available quantity of a batch.
11. Farmer verification: only verified farmers can publish produce listings.
12. Payment: payment amounts should correspond to the order total, which is calculated from the order items.
13. Reviews: only customers who have completed a purchase should be allowed to review the relevant farmer or produce.

A CHECK constraint can only look at values in the same row, so rules 9 to 13 cannot be written as CHECK constraints. They depend on data in other tables and need triggers or logic inside a transaction.

An important additional consideration is concurrent purchasing. If two buyers attempt to purchase the remaining stock of the same batch simultaneously, the database must process stock updates safely using transactions and appropriate locking mechanisms. This prevents overselling, and it is demonstrated in Portfolio 3.

## 3. Summary of the design

The central entity is produce_listings (Batch) because it connects the farmer, product and actual available stock. Orders reference individual listings through order_items, while deliveries can be separated by farmer to support orders involving multiple suppliers.

This structure provides a foundation for Farmily to manage different farmers, agricultural products, stock levels, customer orders and regional delivery operations while maintaining data consistency and supporting future expansion.
