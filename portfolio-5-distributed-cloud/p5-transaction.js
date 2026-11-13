// =============================================================================
// Farmily: p5-transaction.js (Portfolio 5)
// Multi-document transactions on the replica set. Placing an order touches two
// documents: a new order and the listing's stock. In Portfolio 4 (one server)
// these could not be made all-or-nothing. On a replica set they can.
//
// Run with the replica set connection string (see replica-set-commands.sh, step 7).
// =============================================================================

const session = db.getMongo().startSession();
const f = session.getDatabase('farmily');

function placeOrder(orderId, listingId, qty) {
  print('\n--- Order ' + orderId + ': ' + qty + ' units of listing ' + listingId + ' ---');
  session.startTransaction({ readConcern: { level: 'snapshot' }, writeConcern: { w: 'majority' } });
  try {
    const listing = f.listings.findOne({ _id: listingId });

    // 1. Save the order first
    f.orders.insertOne({
      _id: orderId,
      customer: { customer_id: 7, name: 'Bola Ade' },
      delivery_address: { street: '4 Wuse Road', city: 'Garki', region: 'Abuja' },
      status: 'paid', order_date: new Date(),
      items: [ { listing_id: listingId, product: listing.product, farmer_id: listing.farmer.farmer_id,
                 quantity: qty, unit_price: listing.price_per_unit } ],
      payments: [ { method: 'card', amount: qty * listing.price_per_unit, status: 'completed', ref: 'TX' + orderId } ],
      deliveries: []
    });
    print('Order inserted (inside the transaction)');

    // 2. Then reduce the stock, only if there is enough
    const res = f.listings.updateOne(
      { _id: listingId, quantity_available: { $gte: qty } },
      { $inc: { quantity_available: -qty } });
    if (res.modifiedCount === 0) throw new Error('not enough stock');

    session.commitTransaction();
    print('COMMITTED: order saved and stock reduced together');
  } catch (e) {
    session.abortTransaction();
    print('ABORTED (' + e.message + '): the order insert above is undone');
  }
  const check = db.getSiblingDB('farmily');
  print('Order ' + orderId + ' exists afterwards? ' + (check.orders.countDocuments({ _id: orderId }) === 1));
  print('Stock of listing ' + listingId + ' now: ' + check.listings.findOne({ _id: listingId }).quantity_available);
}

print('Connected to primary: ' + db.hello().primary);
placeOrder(60001, 22, 20);    // enough stock: commits
placeOrder(60002, 22, 500);   // not enough stock: aborts, the order disappears too
session.endSession();
