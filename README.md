# Advanced Database Systems Portfolio (MIT 8103)

**Student:** Bayo Abdulrahman Zubair
**Student ID:** 301870875
**Programme:** Master of Information Technology, Miva Open University
**Session:** 2026/2027 First Semester

## Case study

**Farmily**, an online farm-produce marketplace (e-commerce platform)

Farmily is a simulated online marketplace, created for this portfolio, based in Nigeria and operating across Lagos, Abuja and Kano. It connects smallholder farmers directly with buyers. It helps buyers access fresh agricultural produce without relying on middlemen, while giving farmers access to a wider market and the opportunity to sell at fairer prices. The system has four main types of users: farmers, who list available produce; buyers, such as households, restaurants and small retailers, who browse products, place orders and make payments; delivery riders, who update delivery statuses; and administrators, who verify farmers, manage product categories and handle disputes. The database stores farmer and buyer profiles, addresses, product categories, produce batches, harvest and expiry dates, grades, prices, available quantities, orders, order items, payments, deliveries and reviews. Key operations include listing produce, searching for products, placing orders, processing payments, automatically updating stock, assigning and tracking deliveries, handling cancellations and refunds, and reviewing farmers. Farmily suits this portfolio because buyers may compete for limited stock, product attributes vary widely, and regional operations naturally suggest a distributed system design.

## Portfolio contents

| Folder | Activity |
|---|---|
| `portfolio-1-database-design/` | Database design and modelling |
| `portfolio-2-query-optimisation/` | Query processing and optimisation |
| `portfolio-3-transactions-concurrency/` | Transactions and concurrency |
| `portfolio-4-nosql/` | NoSQL and advanced data models |
| `portfolio-5-distributed-cloud/` | Distributed and cloud database exercise |

## Tools

- PostgreSQL 16 and MongoDB 7, both running in Docker Desktop
- DBeaver (SQL client) and `psql` / `mongosh` (command-line shells)
- draw.io (ER diagram)
- Git and GitHub

## How to run

Requirements: Docker Desktop and Git. Each portfolio's README gives the full details.

**1. PostgreSQL (Portfolios 1 to 3)**

```
docker run --name farmily-pg -e POSTGRES_PASSWORD=<your-password> -p 5432:5432 -d postgres:16
docker exec -it farmily-pg psql -U postgres -c "CREATE DATABASE farmily;"
```

Then, connected to the `farmily` database (DBeaver or `psql`), run in this order:

1. `portfolio-1-database-design/schema.sql`: creates the 13 tables.
2. `portfolio-2-query-optimisation/sample-data.sql`: loads the synthetic data (about 30 seconds).
3. `portfolio-2-query-optimisation/queries.sql` with `EXPLAIN ANALYZE` for the "before" plans, then `indexes.sql` and `ANALYZE`, then the queries again for the "after" plans.
4. `portfolio-3-transactions-concurrency/01-commit.sql` to `05-isolation-levels.sql`: run step by step in `psql` (`docker exec -it farmily-pg psql -U postgres -d farmily`). Scripts 03 to 05 need two sessions side by side; each step names its window.

**2. MongoDB (Portfolio 4)**

```
docker run --name farmily-mongo -p 27017:27017 -d mongo:7
cd portfolio-4-nosql
docker cp farmily-mongo.js farmily-mongo:/tmp/farmily-mongo.js
docker exec -it farmily-mongo mongosh --quiet /tmp/farmily-mongo.js
```

**3. MongoDB replica set (Portfolio 5)**

Stop the single MongoDB container first (`docker stop farmily-mongo`), then run the steps in `portfolio-5-distributed-cloud/replica-set-commands.sh` one at a time from that folder, waiting where a step says so.

## References

- Federal Republic of Nigeria (2023) *Nigeria Data Protection Act 2023*.
- Gilbert, S. and Lynch, N. (2002) 'Brewer's conjecture and the feasibility of consistent, available, partition-tolerant web services', *ACM SIGACT News*, 33(2), pp. 51–59.
- MIVA Open University (2025) *Advanced Database Systems (MIT 8103)*. Course material.
- MongoDB, Inc. (2025) *MongoDB Manual*: Data Modeling, Schema Validation, Replication, Transactions and Sharding. Available at: https://www.mongodb.com/docs/manual/
- PostgreSQL Global Development Group (2024) *PostgreSQL 16 Documentation*: Using EXPLAIN, Transaction Isolation and Explicit Locking. Available at: https://www.postgresql.org/docs/16/
- Tools and software: PostgreSQL 16, MongoDB 7, Docker Desktop, DBeaver Community, draw.io, Git and GitHub.
- Data: all data in this repository is synthetic. `sample-data.sql` (Portfolio 2) and the sample documents in `farmily-mongo.js` (Portfolio 4) contain made-up names, contact details and transactions.

## AI use declaration

- `portfolio-2-query-optimisation/sample-data.sql`: the synthetic data script was generated with AI assistance (Claude, Anthropic). I checked it by running it against the schema and confirming the row counts of every table (`portfolio-2-query-optimisation/row-counts.png`).
- `portfolio-5-distributed-cloud/replica-set-commands.sh`: the replica set demo script was drafted with AI assistance (Claude, Anthropic). I ran every step myself and checked each result against the screenshots (`p5-1` to `p5-6`).

General help from Claude:

- planning and guidance
- reviewing each deliverable
- the repo README scaffolding
