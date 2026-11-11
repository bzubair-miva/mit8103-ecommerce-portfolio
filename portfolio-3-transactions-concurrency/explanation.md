# Farmily: Transactions, Concurrency Control and Isolation Levels

All demos use listing 3 (Ofada rice) from the Portfolio 2 data, with its stock reset to 50 kg (or 30 kg) at the start. Each demo has its own script (`01-commit.sql` to `05-isolation-levels.sql`) and a screenshot as evidence.

## 1. Transactions and ACID (demos 1 and 2)

A transaction is a group of database operations that succeed or fail as one unit. Placing an order on Farmily is a good example, because it is not one change but five: create the order, add the order line, reduce the listing's stock, record the payment and mark the order as paid. If the system stopped halfway, Farmily could end up with stock taken for an order that does not exist, or a paid order with no payment record. Wrapping the five statements in `BEGIN ... COMMIT` means they all happen or none do.

**Demo 1, COMMIT** (`demo1-commit.png`). All five statements ran inside one transaction and `COMMIT` saved them together. The check queries after the commit showed the stock down from 50 to 30 kg, and order 50002 with status `paid`, a 20 kg line and a payment of 36,865.80 (20 kg × 1,843.29).

**Demo 2, ROLLBACK** (`demo2-rollback.png`). A second order asked for 40 kg when only 30 kg were left. The order and its order line were inserted successfully, but the stock update would have set `quantity_available` to −10, which broke `produce_listings_quantity_available_check`. From that point PostgreSQL treated the transaction as failed and refused every further command ("current transaction is aborted, commands ignored until end of transaction block"). After `ROLLBACK`, the stock was still 30 kg and the check for the order returned 0: even the order inserted *before* the error was gone. That is **atomicity**: a transaction is all or nothing.

The other ACID properties, with Farmily examples:

- **Consistency:** a transaction takes the database from one valid state to another. The CHECK, UNIQUE and foreign key constraints from Portfolio 1 define what "valid" means, and demo 2 shows one of them stopping an invalid state (negative stock) from ever being saved.
- **Isolation:** transactions running at the same time should not interfere with each other as if they were mixed together. Demos 3 to 5 show what happens when they do, and how PostgreSQL controls it.
- **Durability:** once `COMMIT` returns, the order stays saved, even if the server crashes a second later. PostgreSQL makes this possible by writing every change to its write-ahead log (WAL) on disk before confirming the commit, and replaying the log when it restarts.

**Why order numbers have gaps.** `order_id` comes from a sequence (an identity column). When the rolled-back order in demo 2 asked for its number, the sequence handed it out, and `ROLLBACK` did not give it back. This is deliberate. If sequences were rolled back, every transaction that took a number would have to lock the sequence until it finished, so that no one else took the next number in the meantime, and all checkouts would queue behind each other. PostgreSQL instead treats a used number as gone. An order number only needs to be unique, not consecutive, so the gaps do no harm.

## 2. The concurrency problem (demo 3)

Demo 3 (`demo3-lost-update.png`) simulates two buyers trying to buy the last 50 kg of rice at the same moment, in two psql sessions at PostgreSQL's default isolation level, READ COMMITTED. Buyer A and Buyer B both started a transaction and read the stock: both saw 50. Each then placed an order for 50 kg and, like a naive application, worked out the new stock itself (50 − 50 = 0) and wrote 0 back. After both committed, the stock showed 0, but the check query found **2 orders and 100 kg sold from a 50 kg batch**. Buyer A's update was overwritten by Buyer B's, which was based on the same old value. This is a **lost update**.

**Why the row lock did not prevent it.** When Buyer B ran its `UPDATE` in step 4, it did have to wait, because Buyer A's update had locked the row. Once A committed, B's update went ahead. The lock only made the two *writes* happen one after the other. The problem was earlier: B decided to write 0 based on the 50 it had read in step 2, and that value was already out of date by the time B wrote. A lock taken at write time cannot correct a decision made from a stale read.

**Why the CHECK constraint did not catch it.** `CHECK (quantity_available >= 0)` only looks at the new value of the row. Both buyers wrote 0, which is a perfectly valid value. The constraint has no way of knowing that 100 kg were sold against 50 kg of stock, because that fact is spread across two transactions, not stored in one row.

## 3. Three ways to control it (demo 4)

Each fix repeats the same race: the stock is reset to 50 kg and two buyers try to buy all of it. Only the stock change is shown, to keep the demos short.

**A. `SELECT ... FOR UPDATE`, pessimistic locking** (`demo4a-for-update.png`). Buyer A reads the stock with `FOR UPDATE`, which locks the row at the moment it is read. When Buyer B tried the same, its `SELECT` waited until A had reduced the stock and committed, and then returned **0.00**, the real current stock, so B's order was cancelled. This works because the lock is taken *before* the decision is made, so B can never act on a stale value. The trade-off is waiting: buyers of the same listing queue behind each other for as long as each transaction lasts. If two transactions lock rows in different orders (A locks rice then yam, B locks yam then rice), each waits for the other forever, a **deadlock**. PostgreSQL detects this and cancels one of them, and it can be avoided by always locking listings in the same order, for example by `listing_id`.

**B. Conditional `UPDATE`** (`demo4b-conditional-update.png`). The check and the change are written as one statement: reduce the stock by 50 *only if* at least 50 are left (`WHERE ... AND quantity_available >= 50`). Buyer A's update succeeded and left 0.00. Buyer B's identical update waited for A's row lock, and when A committed, PostgreSQL re-checked B's `WHERE` condition against the new version of the row. With 0 kg left the condition was false, so the result was **`UPDATE 0`** and `(0 rows)`: nothing changed, and the application knows the rice is sold out. Because one statement is atomic, there is no gap between checking and changing for another buyer to slip into. It is the most efficient fix: no extra read, the lock is held only for the update itself, and no retries are needed. Its limitation is that it only works when the whole rule fits in a single statement on the rows being changed.

**C. `REPEATABLE READ`** (`demo4c-repeatable-read.png`). Both buyers made the same mistake as in demo 3, reading 50 and writing 0, but at REPEATABLE READ. Buyer B's update waited for A, and when A committed, PostgreSQL rejected B's update with **"ERROR: could not serialize access due to concurrent update"**. The psql prompt changed to `farmily=!#`, showing that the transaction had failed and could only be rolled back. At this level a transaction works from a snapshot, and PostgreSQL will not let it overwrite a row that someone else changed after that snapshot was taken, because the change would be based on data the transaction never saw. After `ROLLBACK` the stock was 0.00, with only 50 kg sold. The advantage is that ordinary reads never wait for locks, and the database catches the conflict even when the application logic is naive. The cost is that the application must be written to catch this error and retry the whole transaction.

**Recommendation for Farmily.** I would use the **conditional update (B)** to reduce stock at checkout, because stock is a single number on one row, which is exactly the case it handles best, and it involves no waiting on reads and no retries. In an order with several listings, each line's stock update is checked: if any returns `UPDATE 0`, the whole order transaction is rolled back, so the buyer is never charged for something that has sold out. `FOR UPDATE` remains the right tool when the application must read a row and make a more complex decision before changing it.

## 4. Isolation levels (demo 5)

Demo 5 uses a different problem: a buyer is in the middle of checkout while the farmer raises the price of listing 3 from 1,800 to 2,000 naira per kg.

**READ COMMITTED** (`demo5a-read-committed.png`). The buyer read the price (1800.00), the farmer's update was committed in the other window, and the buyer read it again in the same transaction: **2000.00**. The same query returned a different answer within one transaction, a **non-repeatable read**. At READ COMMITTED each *statement* sees all data committed before it started, so a long transaction can see the data change under it.

**REPEATABLE READ** (`demo5b-repeatable-read.png`). The same steps gave **1800.00** both times. Only after `COMMIT` did a new query show 2000.00. PostgreSQL implements this with **MVCC (multi-version concurrency control)**: an update does not overwrite a row in place but creates a new version of it, and each transaction is given a snapshot that decides which versions it can see. The buyer's transaction kept seeing the version that existed when its snapshot was taken, while the farmer's change created a newer version that only later transactions could see. This is also why readers and writers do not block each other in PostgreSQL.

The SQL standard defines four isolation levels by the anomalies each must prevent:

| Isolation level | Dirty read | Non-repeatable read | Phantom read |
|---|---|---|---|
| READ UNCOMMITTED | possible | possible | possible |
| READ COMMITTED | prevented | possible | possible |
| REPEATABLE READ | prevented | prevented | possible |
| SERIALIZABLE | prevented | prevented | prevented |

- A **dirty read** is reading another transaction's changes before it commits; they may still be rolled back.
- A **non-repeatable read** is reading the same row twice and getting different values, as in demo 5a.
- A **phantom read** is running the same query twice and getting a different *set* of rows, because another transaction inserted or deleted matching rows.

PostgreSQL is stricter than the standard requires. It **never allows dirty reads**: if READ UNCOMMITTED is requested it behaves as READ COMMITTED. Its REPEATABLE READ also prevents phantom reads, because the whole transaction works from one snapshot. SERIALIZABLE goes further still and guarantees the result is the same as if the transactions had run one at a time.

**The trade-off.** Stricter levels give a more consistent view of the data, but more transactions fail with serialization errors, so the application needs retry logic, and more work is wasted when it retries. Looser levels never fail this way but allow the anomalies above.

- **Browsing products** suits **READ COMMITTED**, the default. Each page load should show the latest prices and stock, a browse touches nothing that needs protecting, and a price changing between two page loads is normal, not an error.
- **Checkout** suits **REPEATABLE READ**. Demo 5 shows the risk at READ COMMITTED: in `01-commit.sql` the order line (step 2) and the payment (step 4) each read the price separately, so a price change between them would charge the buyer a different amount from the one recorded on the order line. At REPEATABLE READ the whole checkout sees one price. Combined with the conditional update, a clash with another buyer shows up either as `UPDATE 0` or as a serialization error; the application retries once, and the retry sees the real stock and reports the rice as sold out if it has gone.

## 5. Conclusion

Transactions make Farmily's multi-step operations safe: demo 1 saved an order's five changes together, and demo 2 showed a failure undoing all of them. Demo 3 showed that this is not enough when buyers act at the same time, because a decision based on a stale read can oversell stock that every individual constraint considers valid. Locking (A), atomic conditional updates (B) and stricter isolation (C) all prevented it, at different costs in waiting, flexibility and retries. For Farmily, conditional updates inside a REPEATABLE READ checkout give correct stock and prices, while browsing stays at READ COMMITTED for speed and freshness.
