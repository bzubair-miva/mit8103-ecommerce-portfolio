// =============================================================================
// Farmily: farmily-mongo.js (Portfolio 4)
// The Farmily case study as a MongoDB document database.
//
// How to run (Docker container farmily-mongo, from the portfolio-4-nosql folder):
//   docker cp farmily-mongo.js farmily-mongo:/tmp/farmily-mongo.js
//   docker exec -it farmily-mongo mongosh --quiet /tmp/farmily-mongo.js
//
// The script starts from an empty "farmily" database each time, so it can be
// run again safely. Sections 1-3 build the database, sections 4-11 are the
// queries and tests to screenshot.
// =============================================================================

db = db.getSiblingDB('farmily');
db.dropDatabase();

function heading(text) {
  print('\n==================================================================');
  print(text);
  print('==================================================================');
}

// -----------------------------------------------------------------------------
// 1. Collections with schema validation
// MongoDB does not force a fixed schema, but it can still check the fields that
// matter. Here a listing must have a price above 0 and stock of 0 or more, but
// its "attributes" can contain anything, because they differ by product.
// -----------------------------------------------------------------------------
db.createCollection('listings', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['product', 'category', 'farmer', 'harvest_date', 'expiry_date',
                 'unit', 'price_per_unit', 'quantity_available', 'status'],
      properties: {
        price_per_unit:     { bsonType: ['double', 'int', 'long', 'decimal'], minimum: 0, exclusiveMinimum: true },
        quantity_available: { bsonType: ['double', 'int', 'long', 'decimal'], minimum: 0 },
        unit:   { enum: ['kg', 'g', 'litre', 'piece', 'bunch', 'crate'] },
        grade:  { enum: ['A', 'B', 'C'] },
        status: { enum: ['active', 'sold_out', 'expired', 'withdrawn'] },
        attributes: { bsonType: 'object' }
      }
    }
  }
});

db.createCollection('orders', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['customer', 'delivery_address', 'status', 'order_date', 'items'],
      properties: {
        status: { enum: ['pending', 'paid', 'dispatched', 'delivered', 'cancelled'] },
        items:  { bsonType: 'array', minItems: 1 }
      }
    }
  }
});

db.createCollection('farmers');
db.createCollection('customers');
db.createCollection('reviews');

// -----------------------------------------------------------------------------
// 2. Sample data
// A small, hand-made sample: 5 farmers, 4 customers, 12 listings of very
// different produce, 6 orders and 8 reviews.
// -----------------------------------------------------------------------------

// Farmers: profile plus a stored rating summary (updated when a review is added)
db.farmers.insertMany([
  { _id: 416, name: 'Musa Bello Farms',    region: 'Kano',  phone: '08010000416', is_verified: true,  rating: { review_count: 2, avg_rating: 4.5 } },
  { _id: 133, name: 'Ngozi Okafor Farms',  region: 'Abuja', phone: '08010000133', is_verified: true,  rating: { review_count: 2, avg_rating: 4.0 } },
  { _id: 5,   name: 'Adebayo Ojo Farms',   region: 'Lagos', phone: '08010000005', is_verified: true,  rating: { review_count: 2, avg_rating: 3.5 } },
  { _id: 77,  name: 'Halima Garba Farms',  region: 'Kano',  phone: '08010000077', is_verified: true,  rating: { review_count: 2, avg_rating: 5.0 } },
  { _id: 210, name: 'Tunde Afolabi Farms', region: 'Abuja', phone: '08010000210', is_verified: false, rating: { review_count: 0, avg_rating: null } }
]);

// Customers: addresses are embedded, because each customer only has one or two
db.customers.insertMany([
  { _id: 42, name: 'Mama Put Kitchen', customer_type: 'restaurant', email: 'customer42@example.com',
    addresses: [ { address_id: 56, street: '12 Allen Avenue', city: 'Ikeja', region: 'Lagos', instructions: 'Call on arrival' } ] },
  { _id: 7,  name: 'Bola Ade', customer_type: 'household', email: 'customer7@example.com',
    addresses: [ { address_id: 9,  street: '4 Wuse Road', city: 'Garki', region: 'Abuja' },
                 { address_id: 10, street: '18 Gimbiya Street', city: 'Garki', region: 'Abuja' } ] },
  { _id: 15, name: 'Mini Mart 15', customer_type: 'retailer', email: 'customer15@example.com',
    addresses: [ { address_id: 21, street: '3 Zaria Road', city: 'Nassarawa', region: 'Kano' } ] },
  { _id: 88, name: 'Fatima Usman', customer_type: 'household', email: 'customer88@example.com',
    addresses: [ { address_id: 120, street: '40 Admiralty Way', city: 'Ikeja', region: 'Lagos' } ] }
]);

// Listings: the farmer's name and region are copied in (embedded), so a buyer's
// search needs no join. The "attributes" object is different for each kind of
// produce: this is the main reason a document model suits Farmily.
const musa   = { farmer_id: 416, name: 'Musa Bello Farms',    region: 'Kano' };
const ngozi  = { farmer_id: 133, name: 'Ngozi Okafor Farms',  region: 'Abuja' };
const ade    = { farmer_id: 5,   name: 'Adebayo Ojo Farms',   region: 'Lagos' };
const halima = { farmer_id: 77,  name: 'Halima Garba Farms',  region: 'Kano' };

db.listings.insertMany([
  { _id: 3,  product: 'Ofada rice', category: ['Grains', 'Rice'], farmer: musa,
    harvest_date: new Date('2026-08-06'), expiry_date: new Date('2027-05-03'),
    grade: 'B', unit: 'kg', price_per_unit: 1843.29, quantity_available: 50, status: 'active',
    attributes: { variety: 'Ofada', moisture_pct: 12.5, bag_sizes_kg: [25, 50], destoned: true } },
  { _id: 22, product: 'Ofada rice', category: ['Grains', 'Rice'], farmer: ngozi,
    harvest_date: new Date('2026-09-20'), expiry_date: new Date('2027-06-17'),
    grade: 'A', unit: 'kg', price_per_unit: 1969.70, quantity_available: 121.66, status: 'active',
    attributes: { variety: 'Ofada', moisture_pct: 11.8, bag_sizes_kg: [10, 25], destoned: true } },
  { _id: 31, product: 'Local parboiled rice', category: ['Grains', 'Rice'], farmer: halima,
    harvest_date: new Date('2026-07-01'), expiry_date: new Date('2027-03-28'),
    grade: 'C', unit: 'kg', price_per_unit: 1290.00, quantity_available: 300, status: 'active',
    attributes: { variety: 'FARO 44', moisture_pct: 13.9, bag_sizes_kg: [50], destoned: false } },
  { _id: 40, product: 'Tomatoes', category: ['Vegetables', 'Fruit Vegetables'], farmer: halima,
    harvest_date: new Date('2026-11-12'), expiry_date: new Date('2026-11-19'),
    grade: 'A', unit: 'crate', price_per_unit: 28000, quantity_available: 12, status: 'active',
    attributes: { variety: 'Roma', ripeness: 'firm', crate_weight_kg: 25, cold_stored: true } },
  { _id: 41, product: 'Tomatoes', category: ['Vegetables', 'Fruit Vegetables'], farmer: ade,
    harvest_date: new Date('2026-11-13'), expiry_date: new Date('2026-11-18'),
    grade: 'B', unit: 'crate', price_per_unit: 24500, quantity_available: 8, status: 'active',
    attributes: { variety: 'UC82', ripeness: 'ripe', crate_weight_kg: 20, cold_stored: false } },
  { _id: 52, product: 'White yam', category: ['Tubers', 'Yam'], farmer: ngozi,
    harvest_date: new Date('2026-10-02'), expiry_date: new Date('2026-12-31'),
    grade: 'A', unit: 'piece', price_per_unit: 2900, quantity_available: 140, status: 'active',
    attributes: { tuber_size: 'large', avg_weight_kg: 3.2, origin_lga: 'Kuje' } },
  { _id: 60, product: 'Garri (white)', category: ['Tubers', 'Cassava'], farmer: ade,
    harvest_date: new Date('2026-10-15'), expiry_date: new Date('2027-04-13'),
    grade: 'A', unit: 'kg', price_per_unit: 950, quantity_available: 400, status: 'active',
    attributes: { texture: 'fine', sour_level: 'mild', fortified: false } },
  { _id: 71, product: 'Fresh pepper (tatashe)', category: ['Vegetables', 'Fruit Vegetables'], farmer: musa,
    harvest_date: new Date('2026-11-10'), expiry_date: new Date('2026-11-20'),
    grade: 'B', unit: 'kg', price_per_unit: 2750, quantity_available: 60, status: 'active',
    attributes: { colour: 'red', heat_level: 'mild', dried: false } },
  { _id: 85, product: 'Plantain', category: ['Fruits', 'Tropical Fruits'], farmer: ade,
    harvest_date: new Date('2026-11-08'), expiry_date: new Date('2026-11-20'),
    grade: 'A', unit: 'bunch', price_per_unit: 4800, quantity_available: 35, status: 'active',
    attributes: { ripeness: 'unripe', fingers_per_bunch: 14 } },
  { _id: 93, product: 'Ugwu leaves', category: ['Vegetables', 'Leafy Vegetables'], farmer: ngozi,
    harvest_date: new Date('2026-11-14'), expiry_date: new Date('2026-11-18'),
    grade: 'A', unit: 'bunch', price_per_unit: 520, quantity_available: 90, status: 'active',
    attributes: { organic: true, bunch_weight_g: 400 } },
  { _id: 104, product: 'Brown beans (oloyin)', category: ['Legumes', 'Beans'], farmer: halima,
    harvest_date: new Date('2026-06-10'), expiry_date: new Date('2027-04-06'),
    grade: 'A', unit: 'kg', price_per_unit: 2300, quantity_available: 0, status: 'sold_out',
    attributes: { weevil_treated: true, sorted: true, bag_sizes_kg: [5, 25] } },
  { _id: 118, product: 'Tomatoes', category: ['Vegetables', 'Fruit Vegetables'], farmer: musa,
    harvest_date: new Date('2026-10-25'), expiry_date: new Date('2026-11-01'),
    grade: 'C', unit: 'crate', price_per_unit: 19000, quantity_available: 5, status: 'expired',
    attributes: { variety: 'Roma', ripeness: 'overripe', crate_weight_kg: 25, cold_stored: false } }
]);

// Orders: one document holds the whole order. Items, payments and deliveries are
// embedded because they are always read with the order and the lists stay short.
// unit_price is a copy of the price at the time of the order.
db.orders.insertMany([
  { _id: 50002, customer: { customer_id: 42, name: 'Mama Put Kitchen' },
    delivery_address: { street: '12 Allen Avenue', city: 'Ikeja', region: 'Lagos' },
    status: 'delivered', order_date: new Date('2026-11-02T10:15:00Z'),
    items: [ { listing_id: 3,  product: 'Ofada rice', farmer_id: 416, quantity: 20, unit_price: 1843.29 },
             { listing_id: 41, product: 'Tomatoes',   farmer_id: 5,   quantity: 2,  unit_price: 24500 } ],
    payments: [ { method: 'card', amount: 85865.80, status: 'completed', ref: 'TX50002' } ],
    deliveries: [ { farmer_id: 416, rider: 'Sani Lawal', status: 'delivered',
                    dispatched: new Date('2026-11-03T09:00:00Z'), delivered: new Date('2026-11-05T14:00:00Z') },
                  { farmer_id: 5,   rider: 'Kemi Obi',   status: 'delivered',
                    dispatched: new Date('2026-11-03T08:30:00Z'), delivered: new Date('2026-11-03T16:00:00Z') } ] },
  { _id: 50010, customer: { customer_id: 42, name: 'Mama Put Kitchen' },
    delivery_address: { street: '12 Allen Avenue', city: 'Ikeja', region: 'Lagos' },
    status: 'dispatched', order_date: new Date('2026-11-12T08:40:00Z'),
    items: [ { listing_id: 40, product: 'Tomatoes',               farmer_id: 77,  quantity: 3,  unit_price: 28000 },
             { listing_id: 71, product: 'Fresh pepper (tatashe)', farmer_id: 416, quantity: 10, unit_price: 2750 } ],
    payments: [ { method: 'card', amount: 111500, status: 'failed', ref: 'TXF50010' },
                { method: 'bank_transfer', amount: 111500, status: 'completed', ref: 'TX50010' } ],
    deliveries: [ { farmer_id: 77,  rider: 'Yusuf Garba', status: 'in_transit', dispatched: new Date('2026-11-13T07:00:00Z') },
                  { farmer_id: 416, rider: 'Yusuf Garba', status: 'in_transit', dispatched: new Date('2026-11-13T07:10:00Z') } ] },
  { _id: 50014, customer: { customer_id: 7, name: 'Bola Ade' },
    delivery_address: { street: '4 Wuse Road', city: 'Garki', region: 'Abuja' },
    status: 'delivered', order_date: new Date('2026-11-06T17:20:00Z'),
    items: [ { listing_id: 52, product: 'White yam',   farmer_id: 133, quantity: 4, unit_price: 2900 },
             { listing_id: 93, product: 'Ugwu leaves', farmer_id: 133, quantity: 5, unit_price: 520 } ],
    payments: [ { method: 'mobile_money', amount: 14200, status: 'completed', ref: 'TX50014' } ],
    deliveries: [ { farmer_id: 133, rider: 'Amina Eze', status: 'delivered',
                    dispatched: new Date('2026-11-07T09:00:00Z'), delivered: new Date('2026-11-07T15:30:00Z') } ] },
  { _id: 50019, customer: { customer_id: 15, name: 'Mini Mart 15' },
    delivery_address: { street: '3 Zaria Road', city: 'Nassarawa', region: 'Kano' },
    status: 'paid', order_date: new Date('2026-11-14T12:00:00Z'),
    items: [ { listing_id: 31, product: 'Local parboiled rice', farmer_id: 77, quantity: 100, unit_price: 1290 } ],
    payments: [ { method: 'bank_transfer', amount: 129000, status: 'completed', ref: 'TX50019' } ],
    deliveries: [] },
  { _id: 50021, customer: { customer_id: 88, name: 'Fatima Usman' },
    delivery_address: { street: '40 Admiralty Way', city: 'Ikeja', region: 'Lagos' },
    status: 'cancelled', order_date: new Date('2026-11-09T19:45:00Z'),
    items: [ { listing_id: 85, product: 'Plantain', farmer_id: 5, quantity: 2, unit_price: 4800 } ],
    payments: [ { method: 'card', amount: 9600, status: 'refunded', ref: 'TX50021' } ],
    deliveries: [] },
  { _id: 50025, customer: { customer_id: 42, name: 'Mama Put Kitchen' },
    delivery_address: { street: '12 Allen Avenue', city: 'Ikeja', region: 'Lagos' },
    status: 'pending', order_date: new Date('2026-11-15T06:30:00Z'),
    items: [ { listing_id: 60, product: 'Garri (white)', farmer_id: 5, quantity: 25, unit_price: 950 } ],
    payments: [], deliveries: [] }
]);

// Reviews: kept in their own collection and linked by farmer_id, because a busy
// farmer could collect thousands of reviews (a document is limited to 16 MB).
db.reviews.insertMany([
  { customer_id: 42, farmer_id: 416, listing_id: 3,  rating: 5, comment: 'Clean rice, no stones', date: new Date('2026-11-06') },
  { customer_id: 7,  farmer_id: 416, listing_id: 3,  rating: 4, comment: 'Good, delivery was slow', date: new Date('2026-10-20') },
  { customer_id: 7,  farmer_id: 133, listing_id: 52, rating: 4, comment: 'Big tubers', date: new Date('2026-11-08') },
  { customer_id: 88, farmer_id: 133, listing_id: 93, rating: 4, comment: 'Fresh leaves', date: new Date('2026-10-30') },
  { customer_id: 42, farmer_id: 5,   listing_id: 41, rating: 3, comment: 'Some tomatoes were soft', date: new Date('2026-11-04') },
  { customer_id: 15, farmer_id: 5,   listing_id: 60, rating: 4, comment: 'Good garri', date: new Date('2026-10-12') },
  { customer_id: 15, farmer_id: 77,  listing_id: 31, rating: 5, comment: 'Great value', date: new Date('2026-10-01') },
  { customer_id: 42, farmer_id: 77,  listing_id: 40, rating: 5, comment: 'Firm and fresh', date: new Date('2026-09-22') }
]);

// -----------------------------------------------------------------------------
// 3. Indexes (chosen for the queries below)
// -----------------------------------------------------------------------------
db.listings.createIndex({ product: 1, status: 1, price_per_unit: 1 });
db.listings.createIndex({ 'farmer.farmer_id': 1 });
db.orders.createIndex({ 'customer.customer_id': 1, order_date: -1 });
db.orders.createIndex({ 'items.farmer_id': 1 });   // multikey index on an array field
db.reviews.createIndex({ farmer_id: 1 });

heading('DATABASE BUILT: documents per collection');
['farmers', 'customers', 'listings', 'orders', 'reviews'].forEach(c =>
  print(c.padEnd(10) + db.getCollection(c).countDocuments()));

const today = new Date('2026-11-15');

// -----------------------------------------------------------------------------
// 4. Q1 (buyer): active, unexpired Ofada rice, cheapest first.
// One query, no join: the farmer's name and region are already in each listing.
// -----------------------------------------------------------------------------
heading('Q1  Buyer: active Ofada rice, cheapest first');
db.listings.find(
  { product: 'Ofada rice', status: 'active', expiry_date: { $gt: today } },
  { _id: 1, 'farmer.name': 1, 'farmer.region': 1, grade: 1, price_per_unit: 1, quantity_available: 1 }
).sort({ price_per_unit: 1 }).forEach(d => printjson(d));

// -----------------------------------------------------------------------------
// 5. Q2 (buyer): search on product-specific attributes.
// Tomatoes and rice have completely different attribute fields, yet both can be
// searched directly. In SQL this needs extra columns or an attribute table.
// -----------------------------------------------------------------------------
heading('Q2a Buyer: firm tomatoes in crates of 20 kg or more');
db.listings.find(
  { product: 'Tomatoes', status: 'active', 'attributes.ripeness': 'firm', 'attributes.crate_weight_kg': { $gte: 20 } },
  { product: 1, 'farmer.name': 1, price_per_unit: 1, attributes: 1 }
).forEach(d => printjson(d));

heading('Q2b Buyer: destoned rice with moisture below 12.5%');
db.listings.find(
  { 'attributes.destoned': true, 'attributes.moisture_pct': { $lt: 12.5 }, status: 'active' },
  { product: 1, 'farmer.name': 1, price_per_unit: 1, attributes: 1 }
).forEach(d => printjson(d));

// -----------------------------------------------------------------------------
// 6. Q3 (buyer): order history for customer 42, newest first, with totals.
// Each order is one document, so its items come back with it: no join needed.
// The total is worked out from the items, not stored.
// -----------------------------------------------------------------------------
heading('Q3  Buyer: order history for customer 42');
db.orders.aggregate([
  { $match: { 'customer.customer_id': 42 } },
  { $sort: { order_date: -1 } },
  { $project: { _id: 1, order_date: 1, status: 1, lines: { $size: '$items' },
                order_total: { $round: [ { $sum: { $map: { input: '$items', as: 'i',
                               in: { $multiply: ['$$i.quantity', '$$i.unit_price'] } } } }, 2 ] } } }
]).forEach(d => printjson(d));

// -----------------------------------------------------------------------------
// 7. Q4 (farmer): sales per product for farmer 416, cancelled orders excluded.
// $unwind turns each order item into its own row so it can be grouped.
// -----------------------------------------------------------------------------
heading('Q4  Farmer 416: sales per product');
db.orders.aggregate([
  { $match: { status: { $ne: 'cancelled' }, 'items.farmer_id': 416 } },
  { $unwind: '$items' },
  { $match: { 'items.farmer_id': 416 } },
  { $group: { _id: '$items.product', orders: { $sum: 1 }, quantity_sold: { $sum: '$items.quantity' },
              revenue: { $sum: { $multiply: ['$items.quantity', '$items.unit_price'] } } } },
  { $sort: { revenue: -1 } }
]).forEach(d => printjson(d));

// -----------------------------------------------------------------------------
// 8. Q5 (admin): best-rated verified farmers.
// Reads the stored rating summary, so no reviews have to be averaged.
// -----------------------------------------------------------------------------
heading('Q5  Admin: verified farmers by stored average rating');
db.farmers.find(
  { is_verified: true, 'rating.review_count': { $gte: 1 } },
  { name: 1, region: 1, rating: 1 }
).sort({ 'rating.avg_rating': -1, 'rating.review_count': -1 }).forEach(d => printjson(d));

// -----------------------------------------------------------------------------
// 9. Adding a review: two writes, the review and the farmer's stored summary.
// The new average is worked out inside the update from the old values.
// -----------------------------------------------------------------------------
heading('Adding a 2-star review for farmer 5 and updating the stored rating');
db.reviews.insertOne({ customer_id: 88, farmer_id: 5, listing_id: 85, rating: 2,
                       comment: 'Plantain arrived bruised', date: today });
db.farmers.updateOne({ _id: 5 }, [
  { $set: { 'rating.avg_rating': { $round: [ { $divide: [
              { $add: [ { $multiply: ['$rating.avg_rating', '$rating.review_count'] }, 2 ] },
              { $add: ['$rating.review_count', 1] } ] }, 2 ] },
            'rating.review_count': { $add: ['$rating.review_count', 1] } } }
]);
printjson(db.farmers.findOne({ _id: 5 }, { name: 1, rating: 1 }));
print('Check against the reviews collection:');
db.reviews.aggregate([
  { $match: { farmer_id: 5 } },
  { $group: { _id: '$farmer_id', review_count: { $sum: 1 }, avg_rating: { $avg: '$rating' } } }
]).forEach(d => printjson(d));

// -----------------------------------------------------------------------------
// 10. Concurrency: the last 50 kg again (same idea as Portfolio 3, Fix B).
// The stock check and the change are one atomic update on one document.
// -----------------------------------------------------------------------------
heading('Conditional stock update: two buyers each want the last 50 kg');
const buyerA = db.listings.updateOne(
  { _id: 3, quantity_available: { $gte: 50 } }, { $inc: { quantity_available: -50 } });
print('Buyer A: matched ' + buyerA.matchedCount + ', modified ' + buyerA.modifiedCount);
const buyerB = db.listings.updateOne(
  { _id: 3, quantity_available: { $gte: 50 } }, { $inc: { quantity_available: -50 } });
print('Buyer B: matched ' + buyerB.matchedCount + ', modified ' + buyerB.modifiedCount + '  (sold out, nothing changed)');
printjson(db.listings.findOne({ _id: 3 }, { product: 1, quantity_available: 1 }));

// -----------------------------------------------------------------------------
// 11. Schema validation: these inserts should be rejected.
// -----------------------------------------------------------------------------
heading('Schema validation: inserts that should be rejected');
try {
  db.listings.insertOne({ product: 'Okra', category: ['Vegetables'], farmer: ade,
    harvest_date: today, expiry_date: new Date('2026-11-22'), unit: 'kg',
    price_per_unit: 1500, quantity_available: -5, status: 'active', attributes: {} });
  print('Negative stock: ACCEPTED (unexpected)');
} catch (e) { print('Negative stock: rejected -> ' + e.message); }

try {
  db.orders.insertOne({ customer: { customer_id: 7, name: 'Bola Ade' },
    delivery_address: { street: '4 Wuse Road', city: 'Garki', region: 'Abuja' },
    status: 'paid', order_date: today, items: [] });
  print('Order with no items: ACCEPTED (unexpected)');
} catch (e) { print('Order with no items: rejected -> ' + e.message); }

// -----------------------------------------------------------------------------
// 12. Index use: does Q1 use the index? (IXSCAN = index, COLLSCAN = full scan)
// -----------------------------------------------------------------------------
heading('Q1 explain(): plan stages and documents examined');
function stages(plan) {
  const out = [plan.stage];
  if (plan.inputStage) out.push(...stages(plan.inputStage));
  if (plan.inputStages) plan.inputStages.forEach(p => out.push(...stages(p)));
  return out;
}
const q1 = { product: 'Ofada rice', status: 'active', expiry_date: { $gt: today } };
const withIndex = db.listings.find(q1).sort({ price_per_unit: 1 }).explain('executionStats');
print('With index:    stages ' + stages(withIndex.queryPlanner.winningPlan).join(' <- ') +
      ' | returned ' + withIndex.executionStats.nReturned +
      ', documents examined ' + withIndex.executionStats.totalDocsExamined);
const noIndex = db.listings.find(q1).sort({ price_per_unit: 1 }).hint({ $natural: 1 }).explain('executionStats');
print('Forced no index: stages ' + stages(noIndex.queryPlanner.winningPlan).join(' <- ') +
      ' | returned ' + noIndex.executionStats.nReturned +
      ', documents examined ' + noIndex.executionStats.totalDocsExamined);

heading('DONE');
