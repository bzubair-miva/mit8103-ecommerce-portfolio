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

- PostgreSQL 16 (Docker)
- MongoDB (Docker)
- pgAdmin / DBeaver
- Git and GitHub

## How to run

_To be added._

## References

_To be added._

## AI use declaration

- `portfolio-2-query-optimisation/sample-data.sql`: the synthetic data script was generated with AI assistance (Claude, Anthropic). I checked it by running it against the schema and confirming the row counts of every table (`portfolio-2-query-optimisation/row-counts.png`).
- `portfolio-5-distributed-cloud/replica-set-commands.sh`: the replica set demo script was drafted with AI assistance (Claude, Anthropic). I ran every step myself and checked each result against the screenshots (`p5-1` to `p5-6`).

General help from Claude:

- planning and guidance
- reviewing each deliverable
- the repo README scaffolding
