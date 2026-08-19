# StoreERP — User Acceptance Test (UAT) Flow

**Purpose:** Step-by-step manual to verify the core business loop end-to-end —
purchase → stock → sales → GST → reporting.

**Environment:** _______________  **Tester:** _______________  **Date:** _______________

> **How to read this:** Do the **Steps** in order. Compare what you see against the
> **Expected result**. Mark each case **Pass / Fail** and note anything off.

---

## Pre-conditions (do once before starting)

| # | Setup | Where |
|---|-------|-------|
| 0.1 | Log in as a store user (`owner` or `admin` role). | `/users/sign_in` |
| 0.2 | Confirm your **organisation** has a State + GSTIN set (needed for GST split). | `/organisations` → edit |
| 0.3 | At least one **product** exists in the catalogue (with HSN + GST rate). | `/setup/products` |
| 0.4 | At least one **supplier** exists (with State — controls CGST/SGST vs IGST). | `/purchasing/suppliers` |
| 0.5 | At least one **customer** exists. | `/customers` |
| 0.6 | Note the **current stock quantity** of the test product for later comparison. | `/inventory/stock_levels` |

---

## TEST 1 — Create a Purchase Bill

A purchase bill can be created **two ways**. Test both (1A and 1B).

### 1A — Manual purchase entry

| Step | Action | Expected result |
|------|--------|-----------------|
| 1A.1 | Go to **Purchasing → Purchase Invoices → New**. | `/purchasing/purchase_invoices/new` opens with an empty invoice form. |
| 1A.2 | Select the **supplier**, enter **invoice number** and **invoice date**. | Header fields accept input. |
| 1A.3 | Add a **line item**: search/select the product, enter **quantity** and **unit rate**. | Line total (taxable amount) calculates automatically. |
| 1A.4 | Add a second line item for a different product (optional). | Second line adds; invoice total updates. |
| 1A.5 | **Save** the invoice. | Invoice is saved as **DRAFT**. No stock has moved yet. |
| 1A.6 | Review the draft, then click **Confirm**. | Status changes **DRAFT → CONFIRMED**; a confirmed-at timestamp appears. |

**Result:** ☐ Pass ☐ Fail — Notes: ______________________________________________

### 1B — Upload soft copy (AI invoice capture)

| Step | Action | Expected result |
|------|--------|-----------------|
| 1B.1 | Go to **Purchasing → Digitise → New**. | `/purchasing/digitise/new` opens an upload screen. |
| 1B.2 | Upload a **photo or PDF** of a supplier invoice. | File uploads; a **DigitiseImport** record is created with status **Pending**. |
| 1B.3 | Wait for background processing. | Status moves **Pending → Processing → Review** (AI reads the bill). |
| 1B.4 | Open the completed scan. | Extracted **supplier, invoice number, line items, quantities, rates and GST** are shown for review. |
| 1B.5 | Review/correct any fields, match unmatched products, then **Confirm**. | A **DRAFT purchase invoice** is created from the extracted data. |
| 1B.6 | Confirm the resulting draft (as in 1A.6). | Status **DRAFT → CONFIRMED**. |

> **Note:** AI output is always a *draft proposal* — a human must confirm before
> stock or tax is posted. If a scan fails, status shows **Failed** and it can be retried.

**Result:** ☐ Pass ☐ Fail — Notes: ______________________________________________

---

## TEST 2 — Stock entry reflects in Inventory

| Step | Action | Expected result |
|------|--------|-----------------|
| 2.1 | Go to **Inventory → Stock Levels**. | `/inventory/stock_levels` lists products with on-hand quantity. |
| 2.2 | Find the product(s) from the confirmed purchase in TEST 1. | On-hand quantity has **increased by the purchased quantity** (vs the value noted in 0.6). |
| 2.3 | Check the **average cost** column. | `avg_cost` reflects the purchase unit rate (moving-average). |
| 2.4 | Open the **Stock Ledger** (Inventory → Opening Stock → Ledger, or product history). | A new movement row with **entry type = purchase** links back to the purchase invoice. |
| 2.5 | (Negative check) Create a purchase but leave it as **DRAFT** — do **not** confirm. | Stock does **NOT** change for a draft. Only confirmation moves stock. |

**Result:** ☐ Pass ☐ Fail — Notes: ______________________________________________

---

## TEST 3 — Sales Invoice Generation

| Step | Action | Expected result |
|------|--------|-----------------|
| 3.1 | Go to **Sales → Sales Invoices → New**. | `/sales/sales_invoices/new` opens an empty sales invoice. |
| 3.2 | Select the **customer**; choose payment mode. | Header accepts input. |
| 3.3 | Add a **line item**: pick the product (in stock from TEST 1), enter **quantity** and **rate**; apply a **discount** if desired. | Line taxable amount, discount and total calculate live. |
| 3.4 | Save the draft, then open **Preview / Review & Confirm**. | Preview shows the full invoice with tax breakdown. |
| 3.5 | Click **Confirm**. | Status **DRAFT → CONFIRMED**; invoice number assigned. |
| 3.6 | Re-open **Inventory → Stock Levels** for that product. | On-hand quantity has **decreased by the sold quantity** (ledger entry type = **sale**). |
| 3.7 | (Optional) **Void** the confirmed invoice. | Status → **VOIDED**; stock is **returned** via an **adjustment** ledger entry. |
| 3.8 | Record a **payment** against the invoice (Sales → receipts). | Payment status updates: **unpaid → partial → paid** as amounts are added. |

**Result:** ☐ Pass ☐ Fail — Notes: ______________________________________________

---

## TEST 4 — Automatic GST

GST is computed automatically at **confirmation** based on supplier/customer State
vs your organisation's State.

| Step | Action | Expected result |
|------|--------|-----------------|
| 4.1 | Open a **confirmed purchase** from a supplier in the **same State** as your org. | Tax is split into **CGST + SGST** (intra-state); each = half the GST rate. |
| 4.2 | Open a **confirmed purchase** from a supplier in a **different State**. | Tax is a single **IGST** amount (inter-state); CGST/SGST = 0. |
| 4.3 | Go to **Accounting → GST**. | GST dashboard opens at `/accounting/gst`. |
| 4.4 | Open **GSTR-1**. | Outward (sales) supplies + **HSN summary** are listed for the period. |
| 4.5 | Open **GSTR-3B**. | Output tax vs eligible **ITC** shown; **net tax payable** computed after set-off. |
| 4.6 | Open **ITC** report. | Input credit from purchases, grouped by GST rate. |
| 4.7 | (Optional) **Close the period**. | Period locks; closing credit carries forward as next month's opening. |

**Verify the maths (spot check):** taxable × rate = tax; CGST + SGST = total GST (intra-state).

**Result:** ☐ Pass ☐ Fail — Notes: ______________________________________________

---

## TEST 5 — Reporting

| Step | Action | Expected result |
|------|--------|-----------------|
| 5.1 | Go to **Reports → Sales** (`/reports/sales`). | Sales for the period appear; totals match the invoices confirmed in TEST 3. |
| 5.2 | Click **Export**. | A CSV downloads with the same figures. |
| 5.3 | Go to **Reports → Purchases** (`/reports/purchases`). | Purchases match TEST 1; export works. |
| 5.4 | Go to **Reports → Stock** (`/reports/stock_reports`). | On-hand quantity and valuation match **Inventory** after TESTS 1–3. |
| 5.5 | Go to **Reports → Cash Flow** (`/reports/cash_flows`). | Money in (receipts) vs money out (supplier payments) reflect recorded payments. |
| 5.6 | Open the **Dashboard** (`/dashboard`). | Month-to-date sales & purchase charts and **payables due** reflect the test data. |

**Result:** ☐ Pass ☐ Fail — Notes: ______________________________________________

---

## End-to-end reconciliation (final check)

After all tests, these should agree with each other:

- [ ] **Stock report** on-hand = opening (0.6) **+ purchases** (TEST 1) **− sales** (TEST 3).
- [ ] **Sales report** total = sum of confirmed sales invoices.
- [ ] **Purchases report** total = sum of confirmed purchase invoices.
- [ ] **GSTR-3B** output tax = GST on confirmed sales; ITC = GST on confirmed purchases.
- [ ] **Cash flow** = recorded receipts and supplier payments only.

---

### Status reference

| Document | States |
|----------|--------|
| Purchase invoice | `DRAFT` → `CONFIRMED` |
| Sales invoice | `DRAFT` → `PREVIEW` → `CONFIRMED` → `VOIDED` |
| Digitise import | `Pending` → `Processing` → `Review` → (`Confirmed` / `Failed`) |
| Stock ledger entry types | `purchase` (+) · `sale` (−) · `opening` · `adjustment` (±) |

_Golden rule: nothing moves stock or tax until a document is **CONFIRMED**._
