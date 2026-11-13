# Farmily: Distributed and Cloud Database Design

This document explains the distributed database built in this portfolio, a three-node MongoDB replica set (`rs0`) holding the Farmily data from Portfolio 4, and extends it into a design for running Farmily at scale. Sections 1 to 3, 5 and 6 are backed by the screenshots `p5-1` to `p5-6`. Sections 4 and 7 are designs that were not built.

## 1. Architecture

The replica set has three nodes, `mongo1`, `mongo2` and `mongo3`, each a MongoDB 7 server in its own Docker container on a private network. `p5-1-replica-set.png` shows their roles after the set was started: one **PRIMARY** (`mongo1`) and two **SECONDARY** nodes.

This is a **client-server** architecture with a **primary-secondary** (master-slave) arrangement among the servers. Clients, such as `mongosh` or the Farmily application, connect with a connection string that lists all three nodes (`mongodb://mongo1:27017,mongo2:27017,mongo3:27017/?replicaSet=rs0`), find out which node is currently primary and send all writes to it. The primary records each change in its operation log (oplog), and the secondaries copy and apply those changes. Only one node accepts writes at a time, which keeps the copies easy to keep consistent.

The textbook describes two other architectures for comparison:

- In a **peer-to-peer** architecture, every node is equal: any node can accept reads and writes, and the nodes coordinate among themselves (Cassandra works this way). There is no single primary to fail, but two nodes can accept conflicting writes to the same data, which must then be resolved.
- A **federated** database system links several **autonomous** databases, often of different types, owned and run separately, behind a shared global schema. Each keeps control of its own data. The replica set is the opposite: one database, one schema, and three identical copies under one administration. Farmily's overall design, with PostgreSQL for orders and MongoDB for the catalogue (Portfolio 4's verdict), is closer to a loosely federated (multidatabase) setup, because two independent systems each own part of the data and the application combines them.

## 2. Replication

The replica set uses **full replication**: every node holds a complete copy of the whole database. `p5-2-replication.png` shows the evidence. The Portfolio 4 data was loaded through the primary, and a session on the secondary `mongo2` (`isWritablePrimary: false`) found all 12 listings and 6 orders already there. When the same session tried to write, it was refused with "not primary": secondaries only accept changes that come from the primary.

**Benefits.**

- **Availability:** if a node fails, two complete copies remain, so no data is lost and the set keeps running (section 3).
- **Read scaling:** reads that can accept slightly old data, such as browsing the catalogue, can be served by the secondaries, which takes load off the primary.

**Costs.**

- **Storage:** three nodes means three times the storage.
- **Write latency:** a write that must be confirmed by a majority (section 5) waits until at least one secondary has copied it, which is slower than a single server. Every write is also applied three times.

**Partial replication** copies only some fragments to some sites. For example, each region's orders could be stored in that region and copied to one other region for safety, rather than to every node. This saves storage and write traffic, but a query may have to visit a site that holds the fragment it needs, and the system must track which fragments are where. Full replication is the simplest choice for three nodes and a small database; partial replication becomes worthwhile as the data grows and is split into fragments (section 4).

## 3. Failover and availability

**Election** (`p5-3-failover.png`). With the primary `mongo1` stopped, the status check from `mongo2` showed `mongo1` as "not reachable/healthy", `mongo2` as the new **PRIMARY** and `mongo3` as SECONDARY. The members send each other heartbeats every few seconds. When the secondaries stopped hearing from the primary, one of them called an election, and `mongo2` won it by collecting votes from a majority of the set: its own and `mongo3`'s, 2 out of 3. The data was still writable through the new primary: listing 22's price was changed to 1990 while `mongo1` was down (`p5-4-rejoin.png`, top).

**Catching up** (`p5-4-rejoin.png`). When `mongo1` was started again, it first rejoined as a secondary and copied the operations it had missed from the oplog, including the price change. It was configured with priority 2 (the others have 1), so once it had caught up it took over as primary again. The final status shows `mongo1` PRIMARY with the other two SECONDARY, and reading listing 22 on `mongo1` returned 1990, a write made while it was switched off. A node never becomes primary while it is behind, so no committed write is lost when roles change.

**Why three nodes.** A new primary can only be elected by a **majority** of the set's members. With three nodes the majority is 2, so the set survives the loss of any one node. With two nodes the majority is also 2, so losing either node leaves one node that can never win an election, and the set stops accepting writes: two nodes are no more available than one. A fourth node does not help either, because the majority of 4 is 3, so it still survives only one failure. Requiring a majority also prevents **split brain**: if the network splits the nodes into two groups, at most one group can contain a majority, so two primaries can never accept conflicting writes at the same time.

## 4. Fragmentation and sharding (design)

The replica set copies all the data to every node; it does not divide it. As Farmily grows, the data would also need to be **fragmented**, split into parts stored on different sites, which MongoDB calls **sharding**.

**Horizontal fragmentation by region.** Farmily operates in three regions, Lagos, Abuja and Kano, which became the `regions` table in Portfolio 1. `orders` and `listings` would be split by row, so that each region's orders and listings live on a shard in or near that region. Region would be the shard key, `delivery_address.region` for orders and `farmer.region` for listings. Both already exist in the Portfolio 4 documents because the address and farmer details are embedded. In the relational design this would be **derived horizontal fragmentation**: `produce_listings` has no region column, so its fragments are derived from the region of each listing's farmer.

- **Benefits:** most activity is local (Lagos buyers mostly buy Lagos stock and Lagos riders deliver it), so most queries are served by one nearby shard, with lower latency and less network traffic. The load is also spread across three sets of servers instead of one.
- **Risks:**
  - **Uneven shards.** Lagos is the busiest region (half the buyer addresses in the Portfolio 2 sample data are in Lagos), so the Lagos shard would hold more data and handle more traffic than the others, a "hot" shard.
  - **Too few shard key values.** A key with only three values cannot be divided further, so the Lagos shard cannot be split across more servers as it grows. A compound key, such as region plus order ID, keeps each region's data together while still allowing a busy region to be divided.
  - **Queries across regions.** A buyer in Abuja ordering rice from a Kano farmer, or an admin report covering all regions, must contact several shards and combine the results, which is slower than a single-shard query.

**Vertical fragmentation.** Vertical fragmentation splits a table by column instead of by row. One example for Farmily is separating customers' sensitive contact details (phone number, email, street addresses) from the order and profile data used every day. The contact fragment could be stored with stricter access control and encryption and read only by the services that deliver orders, while order processing and analytics work from the other fragment. Each fragment keeps `customer_id`, so the original customer record can be rebuilt by joining them when needed.

## 5. Consistency, CAP and BASE

**Writes need a majority (strong consistency).** In MongoDB 7 a write is, by default, only confirmed once a majority of the nodes have it (write concern `majority`); the transactions in section 6 request it explicitly. A confirmed write is therefore on at least two of the three nodes and survives any single failure, and because the election in section 3 also needs a majority, any new primary is guaranteed to have it. Reads from the primary always see the latest confirmed write.

**Reads from secondaries may be slightly behind (eventual consistency).** Secondaries apply the primary's changes a short moment after they happen. A read sent to a secondary, as in `p5-2`, can return data that is slightly out of date, although every secondary eventually catches up. In the demos the delay was too short to see, but the guarantee is weaker. This suits the catalogue, where a price a second old is acceptable, and not checkout.

**The CAP trade-off** (`p5-6-cap.png`). The CAP theorem says that when the network is **partitioned**, a distributed system must choose between **consistency** (every read sees the latest write) and **availability** (every request gets an answer). Stopping `mongo2` and `mongo3` left `mongo1` alone, which from its point of view looks the same as a network split. It could no longer reach a majority, so it **stepped down from PRIMARY to SECONDARY**. Reads still worked (12 listings), but the price update was refused with "not primary". MongoDB chose **consistency over availability for writes**: it would rather refuse writes than risk accepting them on a node that might be cut off from another group that has elected its own primary. That makes the replica set a CP system for writes, while reads stay available at the risk of being stale.

**ACID compared with BASE.** The PostgreSQL database in Portfolio 3 follows **ACID**: transactions are atomic, constraints keep the data consistent, isolation levels control what concurrent transactions see, and commits are durable. On a single server that is natural, because there is only one copy to keep correct. Many distributed NoSQL systems instead follow **BASE**: **B**asically **A**vailable (the system keeps answering even when parts fail), **S**oft state (data may change as replicas catch up) and **E**ventually consistent (copies agree once updates stop). The replica set sits between the two. Majority writes and multi-document transactions give ACID-style guarantees on the primary, while secondary reads behave in a BASE-like way. For Farmily this matches the Portfolio 4 verdict: ACID where money and stock are concerned, BASE-style reads for browsing.

## 6. Transactions in a distributed setting

Portfolio 4 left a gap: placing an order inserts an order document and reduces a listing's stock, which are two documents, and on a single standalone server they could not be made all-or-nothing. Multi-document transactions need a replica set, and `p5-5-transaction.png` shows them working here. Order 60001 for 20 units of listing 22 inserted the order and reduced the stock from 121.66 to 101.66, then committed both together. Order 60002 for 500 units inserted its order, but the conditional stock update matched nothing, so the script aborted the transaction. Afterwards order 60002 did not exist and the stock was still 101.66: the insert that had already happened inside the transaction was undone. This is the same atomicity as `ROLLBACK` in Portfolio 3, demo 2, now in MongoDB.

**The cost is coordination.** The transaction reads from a consistent snapshot (read concern `snapshot`) and its commit waits until a majority of nodes have it (write concern `majority`), so it is slower than single-document writes and holds resources until it finishes. MongoDB also aborts transactions that run longer than 60 seconds by default. Across shards it costs more again, because each shard involved must agree to commit, using a two-phase commit. Transactions should therefore be kept short and used only where several documents must change together, such as placing an order, while single-document updates, such as the conditional stock update from Portfolio 4, remain the normal case.

## 7. Cloud deployment (design)

Following the Portfolio 4 verdict, Farmily would run two managed cloud databases, each where it is strongest:

- **Product catalogue and search: MongoDB Atlas.** A managed MongoDB cluster, deployed as a replica set like the one built here, with members in more than one data centre or region so that the loss of one location does not stop browsing. As traffic grows, the cluster can be sharded by region as in section 4, with each region's data placed in the cloud location nearest to it. Atlas handles elections, patching and backups.
- **Orders, payments and stock: Amazon RDS for PostgreSQL**, the system of record. **Multi-AZ** keeps a standby copy in a second availability zone, kept up to date synchronously, and fails over to it automatically if the primary fails, which gives the same protection as the replica set without data loss. **Read replicas** are updated asynchronously and can serve reports and order history, taking load off the primary, while checkout always uses the primary so that prices and stock are never stale.

Listings would be written to PostgreSQL first and copied to Atlas for searching, so the catalogue may be a few seconds behind, which is acceptable for browsing.

**Trade-offs:** managed services cost more per month than running the database yourself and cost grows with every replica, but automated backups, failover and patching save a great deal of operations work; and because the nearest cloud regions may be outside Nigeria, where Farmily's customer data is stored would have to be checked against Nigeria's data protection law (the Nigeria Data Protection Act 2023) and weighed against latency.
