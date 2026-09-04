# Stock Ledger

Every stock movement, newest first. This is the full history behind the numbers
on **Stock Levels**.

## What the columns mean
- **Type** — what caused the movement:
  - **opening** — your starting count.
  - **purchase** — a purchase bill was confirmed. Stock went up.
  - **sale** — a sales invoice was confirmed. Stock went down.
  - **adjustment** — a manual change, or a voided sales bill putting stock back.
  - **return** — goods returned.
- **Quantity** — how much moved. A minus sign means stock went out.
- **Unit Cost (₹)** — what each unit cost, where it is known.
- **Notes** — which bill caused it.
- **Entered by** — which user.

## Why entries cannot be deleted
The ledger is a permanent record. Nothing here is ever edited or removed — a
correction is added as a **new** entry instead. That way the history always
explains how you arrived at today's figure.

> Tip: if a product's quantity looks wrong, read its entries here from the
> bottom up. The step where it goes wrong tells you which bill to check.
