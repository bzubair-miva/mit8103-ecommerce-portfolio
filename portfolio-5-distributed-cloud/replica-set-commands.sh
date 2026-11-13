#!/bin/bash
# =============================================================================
# Farmily: replica-set-commands.sh (Portfolio 5)
# A 3-node MongoDB replica set (rs0) in Docker, used to show replication,
# automatic failover, multi-document transactions and the CAP trade-off.
#
# Run the steps ONE AT A TIME from the portfolio-5-distributed-cloud folder,
# and take the screenshot named under each step.
# Needs farmily-mongo.js from ../portfolio-4-nosql.
# =============================================================================


# --- STEP 1: create a private network and three MongoDB nodes ----------------
docker network create farmily-net
docker run -d --name mongo1 --network farmily-net mongo:7 --replSet rs0 --bind_ip_all
docker run -d --name mongo2 --network farmily-net mongo:7 --replSet rs0 --bind_ip_all
docker run -d --name mongo3 --network farmily-net mongo:7 --replSet rs0 --bind_ip_all


# --- STEP 2: join the three nodes into replica set rs0 -----------------------
# mongo1 gets priority 2, so it is preferred as primary whenever it is healthy.
docker exec -it mongo1 mongosh --quiet --eval 'rs.initiate({ _id: "rs0", members: [
  { _id: 0, host: "mongo1:27017", priority: 2 },
  { _id: 1, host: "mongo2:27017" },
  { _id: 2, host: "mongo3:27017" } ] })'

# Wait about 10 seconds for the election, then check every node's role.
# SCREENSHOT: p5-1-replica-set.png  (one PRIMARY, two SECONDARY)
docker exec -it mongo1 mongosh --quiet --eval 'rs.status().members.forEach(m => print(m.name.padEnd(15) + m.stateStr))'


# --- STEP 3: load the Portfolio 4 Farmily data into the replica set ----------
# The connection string lists all three nodes, so mongosh finds the primary itself.
docker cp ../portfolio-4-nosql/farmily-mongo.js mongo1:/tmp/farmily-mongo.js
docker exec -it mongo1 mongosh "mongodb://mongo1:27017,mongo2:27017,mongo3:27017/?replicaSet=rs0" --quiet /tmp/farmily-mongo.js


# --- STEP 4: replication: read the data on a SECONDARY -----------------------
# The data was written to the primary (mongo1) but is already on mongo2.
# A write sent straight to the secondary is refused.
# SCREENSHOT: p5-2-replication.png
docker exec -it mongo2 mongosh --quiet --eval '
  db.getMongo().setReadPref("secondary");
  const f = db.getSiblingDB("farmily");
  print("mongo2 is primary? " + db.hello().isWritablePrimary);
  print("Listings on mongo2: " + f.listings.countDocuments());
  print("Orders on mongo2:   " + f.orders.countDocuments());
  try { f.listings.insertOne({ test: 1 }); print("Write on secondary: ACCEPTED (unexpected)"); }
  catch (e) { print("Write on secondary: refused -> " + e.message); }'


# --- STEP 5: failover: stop the primary --------------------------------------
docker stop mongo1
# Wait about 15 seconds, then ask mongo2 for the roles.
# SCREENSHOT: p5-3-failover.png  (mongo1 not reachable, a new PRIMARY elected)
docker exec -it mongo2 mongosh --quiet --eval 'rs.status().members.forEach(m => print(m.name.padEnd(15) + m.stateStr))'

# The data is still there and still writable through the new primary:
docker exec -it mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/?replicaSet=rs0" --quiet --eval '
  const f = db.getSiblingDB("farmily");
  print("Primary is now: " + db.hello().primary);
  f.listings.updateOne({ _id: 22 }, { $set: { price_per_unit: 1990.00 } });
  printjson(f.listings.findOne({ _id: 22 }, { product: 1, price_per_unit: 1 }));'


# --- STEP 6: bring the old primary back --------------------------------------
docker start mongo1
# Wait about 20 seconds. mongo1 catches up on the change it missed and, having
# the higher priority, becomes primary again.
# SCREENSHOT: p5-4-rejoin.png
docker exec -it mongo1 mongosh --quiet --eval '
  rs.status().members.forEach(m => print(m.name.padEnd(15) + m.stateStr));
  db.getMongo().setReadPref("primaryPreferred");
  printjson(db.getSiblingDB("farmily").listings.findOne({ _id: 22 }, { product: 1, price_per_unit: 1 }));'


# --- STEP 7: a multi-document transaction (order + stock together) -----------
# SCREENSHOT: p5-5-transaction.png
docker cp p5-transaction.js mongo1:/tmp/p5-transaction.js
docker exec -it mongo1 mongosh "mongodb://mongo1:27017,mongo2:27017,mongo3:27017/?replicaSet=rs0" --quiet /tmp/p5-transaction.js


# --- STEP 8: CAP: lose the majority ------------------------------------------
# Stop two of the three nodes. mongo1 can no longer see a majority, so it
# steps down: it stays readable but refuses writes (consistency over availability).
docker stop mongo2 mongo3
# Wait about 15 seconds.
# SCREENSHOT: p5-6-cap.png
docker exec -it mongo1 mongosh --quiet --eval '
  rs.status().members.forEach(m => print(m.name.padEnd(15) + m.stateStr));
  db.getMongo().setReadPref("secondaryPreferred");
  const f = db.getSiblingDB("farmily");
  print("Read still works: " + f.listings.countDocuments() + " listings");
  try { f.listings.updateOne({ _id: 22 }, { $set: { price_per_unit: 2100 } }); print("Write: ACCEPTED (unexpected)"); }
  catch (e) { print("Write refused -> " + e.message); }'

# Restore the full set afterwards:
docker start mongo2 mongo3
