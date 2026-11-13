# Portfolio 5: Distributed and Cloud Database Exercise

## What I did

I built a three-node MongoDB replica set in Docker, loaded the Farmily data from Portfolio 4 into it, and used it to demonstrate replication, automatic failover and recovery, multi-document transactions and the CAP trade-off. `distributed-design.md` explains the results using distributed database concepts and extends them into a design for sharding Farmily by region and deploying it in the cloud.

## Files

- `replica-set-commands.sh`: the Docker and `mongosh` commands for every step, run one at a time, with the screenshot each step produces.
- `p5-transaction.js`: two orders placed as multi-document transactions, one that commits and one that aborts.
- `p5-1-replica-set.png`: the replica set started: one PRIMARY, two SECONDARY.
- `p5-2-replication.png`: the data read on a secondary, and a write to the secondary refused.
- `p5-3-failover.png`: the primary stopped, and a new primary elected.
- `p5-4-rejoin.png`: a write through the new primary, then the old primary rejoining, catching up and becoming primary again.
- `p5-5-transaction.png`: the committed and the aborted transaction.
- `p5-6-cap.png`: two nodes stopped; the remaining node steps down, still serves reads and refuses writes.
- `distributed-design.md`: architecture, replication, failover, fragmentation and sharding, consistency (CAP, ACID and BASE), distributed transactions, and cloud deployment.

## How I implemented it

- **Three nodes:** three containers (`mongo1`, `mongo2`, `mongo3`) from the `mongo:7` image, on a private Docker network (`farmily-net`), each started with `--replSet rs0`. They are separate from the single `farmily-mongo` container used in Portfolio 4.
- **Replica set:** `rs.initiate()` joined the three nodes into `rs0`. `mongo1` was given priority 2, so it is preferred as primary whenever it is healthy, which makes the failover and rejoin steps predictable.
- **Data:** the Portfolio 4 script, `farmily-mongo.js`, was run through a connection string listing all three nodes, so `mongosh` found the primary itself and the data was replicated to the secondaries.
- **Demos:** I ran the steps in `replica-set-commands.sh` one at a time: check replication on a secondary, stop the primary, write through the new primary, restart the old primary, run `p5-transaction.js`, then stop two nodes to remove the majority. I waited 10 to 20 seconds after each stop or start for the election to finish before checking the result, and took a screenshot at each step.
- **Design sections:** sharding by region and cloud deployment were designed rather than built; they are in `distributed-design.md`, sections 4 and 7.

## How I tested it

| Step | Expected result | Actual result |
|---|---|---|
| 1. Start the replica set | One primary, two secondaries | `mongo1` PRIMARY, `mongo2` and `mongo3` SECONDARY (`p5-1`) |
| 2. Replication | All data on the secondary; writes to it refused | `mongo2` not primary; 12 listings, 6 orders; write refused, "not primary" (`p5-2`) |
| 3. Failover | A new primary elected from the remaining two | `mongo1` not reachable; `mongo2` PRIMARY, `mongo3` SECONDARY (`p5-3`) |
| 4. Write during failover | Still writable through the new primary | "Primary is now: mongo2:27017"; listing 22 price set to 1990 (`p5-4`) |
| 5. Rejoin | Old primary catches up and becomes primary again | `mongo1` PRIMARY again; listing 22 shows 1990 on `mongo1` (`p5-4`) |
| 6. Transaction commits | Order saved and stock reduced together | Order 60001 exists; stock 121.66 → 101.66 (`p5-5`) |
| 7. Transaction aborts | The order insert is undone | Order 60002 does not exist; stock still 101.66 (`p5-5`) |
| 8. Majority lost (CAP) | Remaining node steps down; reads work, writes refused | `mongo1` SECONDARY; read 12 listings; write refused, "not primary" (`p5-6`) |

Every step produced the expected result. Afterwards `mongo2` and `mongo3` were started again to restore the full set.

## Notes

- The demo script (`replica-set-commands.sh`) was drafted with AI assistance (Claude). I ran every step myself and checked each result against the screenshots.
- Stopping two containers in step 8 simulates a network partition from `mongo1`'s point of view: it cannot tell whether the other nodes have failed or are cut off, which is exactly the situation the CAP theorem describes.
