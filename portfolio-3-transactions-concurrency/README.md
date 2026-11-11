# Portfolio 3: Transactions and Concurrency

## What I did

I used the Farmily database from Portfolios 1 and 2 to demonstrate transactions and concurrency control in PostgreSQL. Five demos show a committed and a rolled-back order, a lost update when two buyers buy the same stock at once, three ways to prevent it, and how READ COMMITTED and REPEATABLE READ differ. `explanation.md` explains each result and recommends which approach Farmily should use.

## Files

**Scripts** (run step by step, in the window each step names):

- `01-commit.sql`: places an order (order, order line, stock reduction, payment and status change) as one transaction, ended with `COMMIT`.
- `02-rollback.sql`: an order for more stock than is left; the CHECK constraint fails and `ROLLBACK` undoes the whole transaction.
- `03-lost-update.sql`: two buyers buy the last 50 kg at the same time, and 100 kg are sold (two sessions).
- `04-fixes.sql`: the same race fixed three ways: A `SELECT ... FOR UPDATE`, B a conditional `UPDATE`, C `REPEATABLE READ` (two sessions).
- `05-isolation-levels.sql`: a price change during checkout under READ COMMITTED and under REPEATABLE READ (two sessions).

**Screenshots** (evidence for each demo):

- `demo1-commit.png`: all five changes committed; stock 30 kg, order paid.
- `demo2-rollback.png`: the CHECK error, "commands ignored", and the order gone after `ROLLBACK`.
- `demo3-lost-update.png`: 2 orders and 100 kg sold from 50 kg.
- `demo4a-for-update.png`: Buyer B's `FOR UPDATE` read returns 0.00 after Buyer A commits.
- `demo4b-conditional-update.png`: Buyer B's conditional update returns `UPDATE 0`.
- `demo4c-repeatable-read.png`: Buyer B's update fails with a serialization error.
- `demo5a-read-committed.png`: the price changes from 1800.00 to 2000.00 inside one transaction.
- `demo5b-repeatable-read.png`: the price stays at 1800.00 until the transaction ends.

**Write-up:** `explanation.md` covers ACID, the lost update, the three concurrency control methods and the isolation levels.

## How I implemented it

- **Database:** the `farmily` database in the PostgreSQL 16 Docker container from Portfolio 1 (`farmily-pg`), with the Portfolio 2 sample data. All demos use listing 3 (Ofada rice), whose stock or price is reset at the start of each demo so it can be repeated.
- **Two sessions:** concurrency can only be shown with two transactions open at the same time, so I opened two `psql` sessions side by side in the terminal, each with `docker exec -it farmily-pg psql -U postgres -d farmily`. Window 1 played one buyer and Window 2 the other buyer (or the farmer, in demo 5), and I ran the script steps one at a time, in order, in the window each step names.
- **Why `psql` rather than DBeaver:** DBeaver runs in auto-commit mode by default, committing each statement as soon as it runs. A transaction therefore cannot be held open while the other window acts, which is the whole point of these demos. `psql` only commits when told to, and its prompt shows the transaction state: `farmily=#` outside a transaction, `farmily=*#` inside one, and `farmily=!#` when the transaction has failed (as in demo 4C).

## How I tested it

| Demo | Expected result | Actual result |
|---|---|---|
| 1. COMMIT | All five changes saved; stock 50 → 30 kg; order `paid` | Stock 30.00; order 50002 `paid`, 20 kg, payment 36,865.80 |
| 2. ROLLBACK | CHECK fails at −10; transaction aborted; nothing saved | CHECK error, "commands ignored…"; stock still 30.00; order count 0 |
| 3. Lost update | Both buyers succeed; 100 kg sold from 50 kg | Stock 0.00, but 2 orders and 100.00 kg sold |
| 4A. `FOR UPDATE` | Buyer B waits, then sees 0 and cancels | B's read returned 0.00 after A committed; B rolled back |
| 4B. Conditional `UPDATE` | Buyer B's update changes nothing | `UPDATE 0`, `(0 rows)`; stock 0.00 |
| 4C. `REPEATABLE READ` | Buyer B's update is rejected | "could not serialize access due to concurrent update"; stock 0.00 |
| 5A. READ COMMITTED | The second read sees the new price | 1800.00, then 2000.00 in the same transaction |
| 5B. REPEATABLE READ | Both reads see the same price | 1800.00 both times; 2000.00 only after `COMMIT` |

Every demo produced the expected result.

## Notes

- The demos in `04-fixes.sql` only change the stock, to keep them short. In the real application the order, order line and payment would be part of the same transaction, as in `01-commit.sql`.
- Order numbers have gaps because sequence values are not rolled back; `explanation.md` (section 1) explains why this is intended.
