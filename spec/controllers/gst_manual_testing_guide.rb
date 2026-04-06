# GST Module — Manual QA Testing Guide
# ======================================
# Covers: intra-state (CGST+SGST), inter-state (IGST), ITC set-off,
#         GSTR-1, GSTR-3B, ITC Register, HSN Summary
#
# Run these steps in sequence in your development/staging environment.
# Each step tells you exactly what to do and what to verify.

## PRE-CONDITIONS — Do these once before any test
# ─────────────────────────────────────────────────
# [ ] rails db:migrate (all migrations including 20260330000001 and 20260330000002)
# [ ] Log in as an admin or owner user
# [ ] Go to Organisation Settings → Edit:
#       State:       West Bengal
#       State Code:  19
#       GSTIN:       19AAAAA0000A1Z5  (any valid format)
#     Save. Verify the show page displays all four fields.

## MASTER DATA SETUP
# ─────────────────────────────────────────────────

### Suppliers (needed for purchases)
# Supplier 1 — INTRA-STATE (same state)
#   Name:         Sharma Paints Wholesale
#   State:        West Bengal
#   State Code:   19
#
# Supplier 2 — INTER-STATE (different state)
#   Name:         Ultratech Mumbai Distributor
#   State:        Maharashtra
#   State Code:   27

### Customers (needed for sales)
# Customer 1 — INTRA-STATE
#   Name:         Local Contractor Kolkata
#   State:        West Bengal
#   State Code:   19
#   GSTIN:        (leave blank — will go to B2C in GSTR-1)
#
# Customer 2 — INTRA-STATE B2B
#   Name:         Kolkata Hardware Pvt Ltd
#   State:        West Bengal
#   State Code:   19
#   GSTIN:        19BBBBB1234B1Z5
#
# Customer 3 — INTER-STATE
#   Name:         Bihar Construction Co
#   State:        Bihar
#   State Code:   10
#   GSTIN:        (leave blank)

### Products
# Product 1: Asian Paints Tractor Emulsion 20L
#   GST Rate: 18%    HSN: 32081090
#
# Product 2: Mild Steel Rod 10mm
#   GST Rate: 12%    HSN: 72141000
#
# Product 3: OPC Cement 50kg
#   GST Rate: 28%    HSN: 25010010

# ═══════════════════════════════════════════════════════════════════════════
# TEST BLOCK 1: INTRA-STATE PURCHASE (CGST + SGST)
# ═══════════════════════════════════════════════════════════════════════════

### TC-M01 — Create intra-state purchase invoice
# 1. Go to Purchasing → New Purchase Invoice
# 2. Supplier: Sharma Paints Wholesale (West Bengal)
# 3. Invoice Date: today / any date in the current month
# 4. Add line item:
#      Product:      Asian Paints Tractor Emulsion 20L
#      Qty:          20
#      Total Amount: 23600  ← enter this as the GST-inclusive total
# 5. Click Save (draft)
# 6. Click Confirm

# EXPECTED after confirm:
# ┌─────────────────────────────────────────────────────┐
# │ Field             Value                              │
# ├─────────────────────────────────────────────────────┤
# │ Status            confirmed                          │
# │ Line: gst_rate    18.00                              │
# │ Line: taxable     ₹ 20,000.00  (23600 / 1.18)       │
# │ Line: tax_amount  ₹  3,600.00  (23600 - 20000)       │
# │ Line: supply_type intra_state                        │
# │ Line: cgst_amount ₹  1,800.00  (3600 / 2)            │
# │ Line: sgst_amount ₹  1,800.00  (3600 / 2)            │
# │ Line: igst_amount ₹      0.00                        │
# │ Invoice total_taxable_amount  ₹ 20,000.00            │
# │ Invoice total_tax_amount      ₹  3,600.00            │
# └─────────────────────────────────────────────────────┘
#
# VERIFY IN DB (rails console):
#   item = PurchaseInvoiceItem.last
#   item.supply_type    # => "intra_state"
#   item.cgst_amount    # => 1800.0
#   item.sgst_amount    # => 1800.0
#   item.igst_amount    # => 0.0
#   item.taxable_amount # => 20000.0


# ═══════════════════════════════════════════════════════════════════════════
# TEST BLOCK 2: INTER-STATE PURCHASE (IGST) — The key IGST test
# ═══════════════════════════════════════════════════════════════════════════

### TC-M02 — Create inter-state purchase invoice
# 1. Go to Purchasing → New Purchase Invoice
# 2. Supplier: Ultratech Mumbai Distributor (Maharashtra)  ← CRITICAL
# 3. Invoice Date: same month as TC-M01
# 4. Add line item:
#      Product:      OPC Cement 50kg
#      Qty:          50
#      Total Amount: 22400  ← 50 bags × ₹448 incl. 28% GST
# 5. Save → Confirm

# EXPECTED after confirm:
# ┌─────────────────────────────────────────────────────┐
# │ Field             Value                              │
# ├─────────────────────────────────────────────────────┤
# │ Line: gst_rate    28.00                              │
# │ Line: taxable     ₹ 17,500.00  (22400 / 1.28)       │
# │ Line: tax_amount  ₹  4,900.00  (22400 - 17500)       │
# │ Line: supply_type inter_state   ← MUST be inter     │
# │ Line: cgst_amount ₹      0.00   ← MUST be zero      │
# │ Line: sgst_amount ₹      0.00   ← MUST be zero      │
# │ Line: igst_amount ₹  4,900.00   ← MUST equal tax    │
# └─────────────────────────────────────────────────────┘
#
# VERIFY IN DB:
#   item = PurchaseInvoiceItem.last
#   item.supply_type    # => "inter_state"
#   item.cgst_amount    # => 0.0
#   item.igst_amount    # => 4900.0
#   item.metadata['supply_type']   # => "inter_state"
#   item.metadata['igst_amount']   # => 4900.0

# !! If supply_type = "intra_state" on this item, the state comparison failed.
# !! Check: Organisation.first.state  and  Supplier.find_by(name: 'Ultratech...').state
# !! They must be different strings (case-insensitive).


# ═══════════════════════════════════════════════════════════════════════════
# TEST BLOCK 3: INTRA-STATE SALE (CGST + SGST output)
# ═══════════════════════════════════════════════════════════════════════════

### TC-M03 — Create intra-state sale (B2C, no GSTIN)
# 1. Sales → New Sales Invoice
# 2. Customer: Local Contractor Kolkata (West Bengal, no GSTIN)
# 3. Invoice Date: same month
# 4. Add line item:
#      Product:      Asian Paints Tractor Emulsion 20L
#      Qty:          5
#      Total Amount: 7080  ← 5 × ₹1416 incl. 18% GST
#      CGST%: 9   SGST%: 9
# 5. Confirm

# EXPECTED:
# ┌─────────────────────────────────────────────────────┐
# │ Field             Value                              │
# ├─────────────────────────────────────────────────────┤
# │ Line: supply_type intra_state                        │
# │ Line: gst_rate    18.00                              │
# │ Line: taxable     ₹  6,000.00  (7080 / 1.18)        │
# │ Line: cgst_amount ₹    540.00  (6000 × 9%)           │
# │ Line: sgst_amount ₹    540.00  (6000 × 9%)           │
# │ Line: igst_amount ₹      0.00                        │
# └─────────────────────────────────────────────────────┘

### TC-M04 — Create intra-state sale (B2B, with GSTIN)
# 1. Sales → New Sales Invoice
# 2. Customer: Kolkata Hardware Pvt Ltd (West Bengal, has GSTIN)
# 3. Add line item:
#      Product: Mild Steel Rod 10mm   Qty: 20   Total: 22400
#      CGST%: 6   SGST%: 6
# 4. Confirm

# EXPECTED:
#   supply_type:  intra_state
#   taxable:      20000.00  (22400 / 1.12)
#   cgst_amount:  1200.00   (20000 × 6%)
#   sgst_amount:  1200.00
#   igst_amount:  0.00

# This invoice MUST appear in GSTR-1 B2B section (has GSTIN).

### TC-M05 — Create INTER-STATE sale (IGST output)
# 1. Sales → New Sales Invoice
# 2. Customer: Bihar Construction Co (Bihar, NO GSTIN)  ← CRITICAL
# 3. Invoice Date: same month
# 4. Add line item:
#      Product:      Asian Paints Tractor Emulsion 20L
#      Qty:          10
#      Total Amount: 14160  ← 10 × ₹1416 incl. 18% GST
#      CGST%: 9   SGST%: 9
# 5. Confirm

# EXPECTED — The system detects Bihar ≠ West Bengal:
# ┌─────────────────────────────────────────────────────┐
# │ Field             Value                              │
# ├─────────────────────────────────────────────────────┤
# │ Line: supply_type inter_state  ← MUST be inter      │
# │ Line: gst_rate    18.00                              │
# │ Line: taxable     ₹ 12,000.00                       │
# │ Line: cgst_amount ₹      0.00  ← MUST be zero       │
# │ Line: sgst_amount ₹      0.00  ← MUST be zero       │
# │ Line: igst_amount ₹  2,160.00  ← MUST equal tax_amt │
# │ Line: metadata cgst_percent   0.0                   │
# │ Line: metadata igst_percent  18.0                   │
# └─────────────────────────────────────────────────────┘
#
# VERIFY IN DB:
#   item = SalesInvoiceItem.last
#   item.supply_type    # => "inter_state"
#   item.cgst_amount    # => 0.0
#   item.igst_amount    # => 2160.0
#   item.metadata['igst_percent']  # => 18.0
#   item.metadata['cgst_percent']  # => 0.0

# !! COMMON FAILURE: if supply_type = "intra_state" here, check:
# !!   Customer.find_by(name: 'Bihar Construction...').state  # must be "Bihar"
# !!   Organisation.first.state  # must be "West Bengal"
# !!   Both must be present and different.


# ═══════════════════════════════════════════════════════════════════════════
# TEST BLOCK 4: GST DASHBOARD — Verify summary
# ═══════════════════════════════════════════════════════════════════════════

### TC-M06 — GST Dashboard check
# 1. Go to Accounting → GST (sidebar)
# 2. Select current month in the period selector

# EXPECTED (based on TC-M01 through TC-M05 above):
#
# Purchase ITC earned this month:
#   CGST ITC = 1800 (from TC-M01, intra-state paint)
#   SGST ITC = 1800 (from TC-M01)
#   IGST ITC = 4900 (from TC-M02, inter-state cement)
#   Total ITC = 8500
#
# Sales output tax this month:
#   CGST output = 540 + 1200 = 1740  (TC-M03 + TC-M04)
#   SGST output = 540 + 1200 = 1740  (TC-M03 + TC-M04)
#   IGST output = 2160               (TC-M05)
#   Total output = 5640
#
# Net (Output - ITC):
#   CGST net = 1740 - 1800 = -60  (credit ₹60)
#   SGST net = 1740 - 1800 = -60  (credit ₹60)
#   IGST net = 2160 - 4900 = -2740 (credit ₹2740)
#   Total net = 5640 - 8500 = -2860 (credit, no cash to pay)
#
# ✓ Net GST Payable card should show ₹0 (or show as Credit)
# ✓ Tax head breakdown table should show Credit for all three heads
# ✓ Filing deadlines show GSTR-1 due (11th next month) and GSTR-3B (20th)


# ═══════════════════════════════════════════════════════════════════════════
# TEST BLOCK 5: GSTR-3B — Verify ITC set-off logic
# ═══════════════════════════════════════════════════════════════════════════

### TC-M07 — GSTR-3B ITC set-off verification
# 1. Accounting → GST → GSTR-3B (same month)

# Section 3.1 — Check outward supplies:
#   Total Taxable Value = 6000 + 20000 + 12000 = 38000
#   CGST output = 1740
#   SGST output = 1740
#   IGST output = 2160

# Section 4 — Check ITC available:
#   Inward supplies (CGST): 1800
#   Inward supplies (SGST): 1800
#   Inward supplies (IGST): 4900

# Section 5.1 — Payment of Tax (7-step algorithm):
#
#   IGST row:
#     Tax payable: 2160
#     ITC IGST used: 2160  (Step 1: IGST vs IGST)
#     Net cash: 0.00
#
#   CGST row:
#     Tax payable: 1740
#     ITC IGST used: 1740  (Step 2: remaining IGST vs CGST)
#     Net cash: 0.00
#
#   SGST row:
#     Tax payable: 1740
#     ITC IGST used: 960   (Step 3: remaining IGST = 4900-2160-1740=1000 ... minus rounding)
#     ITC SGST used: 780   (Step 6: SGST ITC covers remaining SGST)
#     Net cash: 0.00
#
# ✓ Bottom box should show GREEN "No GST cash payment required"
# ✓ Total Net Cash Payable = 0.00

# !! If CGST cannot offset SGST (or vice versa), the forbidden cross-offset
# !! buttons/cells should NOT appear in Section 5.1 at all.


# ═══════════════════════════════════════════════════════════════════════════
# TEST BLOCK 6: GSTR-1 — Outward supplies breakdown
# ═══════════════════════════════════════════════════════════════════════════

### TC-M08 — GSTR-1 B2B vs B2C split
# 1. Accounting → GST → GSTR-1 (same month)

# B2B Section (Table 4):
#   ✓ Shows TC-M04 invoice (Kolkata Hardware Pvt Ltd — has GSTIN)
#   ✓ GSTIN column populated
#   ✓ CGST = 1200, SGST = 1200, IGST = 0

# B2C Section (Table 5/7):
#   ✓ Shows TC-M03 invoice (Local Contractor — no GSTIN)
#   ✓ Shows TC-M05 invoice (Bihar Construction — no GSTIN)
#   Count = 2

# HSN Summary (Table 12):
#   ✓ HSN 32081090 (paints) — taxable = 6000+12000 = 18000, tax = 1080+2160 = 3240
#   ✓ HSN 72141000 (steel)  — taxable = 20000, tax = 2400

# Summary Cards:
#   Total invoices: 3
#   Total taxable:  38000
#   Total tax:      5640


# ═══════════════════════════════════════════════════════════════════════════
# TEST BLOCK 7: ITC Register
# ═══════════════════════════════════════════════════════════════════════════

### TC-M09 — ITC Register verification
# 1. Accounting → GST → ITC Register (same month)

# Summary cards:
#   18% card: taxable=20000, ITC=3600
#   28% card: taxable=17500, ITC=4900
#   Total ITC card: ₹8500

# Line item table (2 rows):
#   Row 1 (intra-state paint):
#     GST%: 18    Taxable: 20000
#     CGST: 1800  SGST: 1800  IGST: —
#
#   Row 2 (inter-state cement):
#     GST%: 28    Taxable: 17500
#     CGST: —     SGST: —     IGST: 4900

# Footer totals:
#   Taxable: 37500   CGST: 1800   SGST: 1800   IGST: 4900   Total: 8500


# ═══════════════════════════════════════════════════════════════════════════
# TEST BLOCK 8: HSN Summary
# ═══════════════════════════════════════════════════════════════════════════

### TC-M10 — HSN Summary side-by-side
# 1. Accounting → GST → HSN Summary (same month)

# Sales panel (outward):
#   HSN 32081090  18%  taxable=18000  tax=3240   (TC-M03 + TC-M05 combined)
#   HSN 72141000  12%  taxable=20000  tax=2400   (TC-M04)

# Purchases panel (inward / ITC):
#   HSN 32081090  18%  taxable=20000  tax=3600   (TC-M01)
#   HSN 25010010  28%  taxable=17500  tax=4900   (TC-M02)

# !! Products with blank HSN code should show "—" not crash


# ═══════════════════════════════════════════════════════════════════════════
# TEST BLOCK 9: EDGE CASES
# ═══════════════════════════════════════════════════════════════════════════

### TC-M11 — Empty period
# 1. Change period selector to a month with no invoices (e.g. Jan 2020)
# 2. All cards should show ₹0
# 3. Tables should show "No data" messages
# 4. No errors (500 pages)

### TC-M12 — Organisation with no State set
# 1. Go to Organisation Settings → Edit → clear the State field → Save
# 2. Create and confirm a purchase from Maharashtra supplier
# 3. Check the purchase_invoice_item.supply_type
#    EXPECTED: 'intra_state' (defaults to intra when org state is blank)
#    (not a crash — graceful default)
# 4. Re-add West Bengal to Organisation State before continuing

### TC-M13 — Walk-in sale (no customer)
# 1. Create a sales invoice with no customer selected
# 2. Add a line item with 18% GST
# 3. Confirm
# 4. Check sales_invoice_item.supply_type
#    EXPECTED: 'intra_state' (no customer state to compare → default intra)
# 5. Verify it appears in GSTR-1 B2C section

### TC-M14 — Zero GST product
# 1. Create a product with GST rate = 0%
# 2. Create and confirm a purchase invoice with this product, total ₹500
# 3. ITC Register for the month should NOT include this item
#    (WHERE tax_amount > 0 filter excludes it)
# 4. GST Dashboard should show no change to ITC

### TC-M15 — Period filter isolation
# 1. Create a confirmed purchase invoice dated LAST month
# 2. Create a confirmed purchase invoice dated THIS month
# 3. Switch the GST Dashboard period selector to last month
#    EXPECTED: Only last month's invoice ITC shown
# 4. Switch to this month
#    EXPECTED: Only this month's invoice ITC shown

### TC-M16 — Filing deadline display
# 1. For the current month's period: GSTR-1 due should be 11th of next month
# 2. For the current month's period: GSTR-3B due should be 20th of next month
# 3. Navigate to GSTR-1 page — @gstr1_due must be populated (no nil strftime error)
# 4. Navigate to GSTR-3B page — @gstr3b_due must be populated
# 5. For a period in the past: both deadlines should show "Overdue" in red


# ═══════════════════════════════════════════════════════════════════════════
# TEST BLOCK 10: VALIDATION — Checking the IGST logic specifically
# ═══════════════════════════════════════════════════════════════════════════

### TC-M17 — State comparison is case-insensitive
# Setup:
#   Organisation state: "West Bengal"
#   Create customer with state: "WEST BENGAL"  (all caps)
# 1. Create and confirm a sale to this customer
# 2. EXPECTED: supply_type = 'intra_state' (same state, different casing)
# 3. EXPECTED: cgst_amount > 0, igst_amount = 0

### TC-M18 — State with whitespace
# Setup:
#   Create customer with state: "  Bihar  " (leading/trailing spaces)
# 1. Create and confirm a sale to this customer
# 2. EXPECTED: supply_type = 'inter_state' (strip() handles whitespace)
# 3. EXPECTED: igst_amount > 0, cgst_amount = 0

### TC-M19 — Changing supplier state after invoice creation
# 1. Create and confirm a purchase from WB supplier (intra-state)
# 2. Note the supply_type = 'intra_state' on the item
# 3. Change the supplier's state to Maharashtra in supplier settings
# 4. Create a NEW purchase invoice from the same supplier and confirm
# 5. EXPECTED: New items = 'inter_state', old confirmed items unchanged
# !! Confirmed invoices are immutable — changing supplier state does not
# !! retroactively change old invoice items.

### TC-M20 — IGST ITC cannot be applied after it is exhausted
# Setup for this scenario (verify in GSTR-3B):
#   IGST ITC: ₹1000 (small amount)
#   CGST output: ₹5000
#   SGST output: ₹5000
#
# Expected set-off:
#   Step 2: IGST ITC 1000 → CGST output (pay 1000 of 5000)
#   Step 3: IGST ITC 0 → SGST output (nothing left, 0 used)
#   Step 4: CGST ITC → remaining CGST 4000 (if CGST ITC available)
#   Step 6: SGST ITC → remaining SGST 5000 (if SGST ITC available)
#
# Key assertion: IGST credit does not double-count.
# Verify in Section 5.1: igst_vs_cgst + igst_vs_sgst + igst_vs_igst ≤ total IGST ITC

# ═══════════════════════════════════════════════════════════════════════════
# QUICK CONSOLE VERIFICATION COMMANDS
# ═══════════════════════════════════════════════════════════════════════════

# Run these in rails console after the manual tests above:

# --- Verify purchase items ---
# PurchaseInvoiceItem.last(5).each do |i|
#   puts "#{i.id}: #{i.supply_type} | CGST:#{i.cgst_amount} SGST:#{i.sgst_amount} IGST:#{i.igst_amount}"
# end

# --- Verify sales items ---
# SalesInvoiceItem.last(5).each do |i|
#   puts "#{i.id}: #{i.supply_type} | CGST:#{i.cgst_amount} SGST:#{i.sgst_amount} IGST:#{i.igst_amount}"
# end

# --- Verify ITC split totals for current month ---
# month_start = Date.today.beginning_of_month
# month_end   = Date.today.end_of_month
# items = PurchaseInvoiceItem
#   .joins(:purchase_invoice)
#   .where(purchase_invoices: { status: 'confirmed', invoice_date: month_start..month_end })
# puts "CGST ITC: #{items.sum(:cgst_amount)}"
# puts "SGST ITC: #{items.sum(:sgst_amount)}"
# puts "IGST ITC: #{items.sum(:igst_amount)}"
# puts "Total ITC: #{items.sum(:tax_amount)}"

# --- Verify output tax for current month ---
# inv_items = SalesInvoiceItem
#   .joins(:sales_invoice)
#   .where(sales_invoices: { status: 'confirmed', invoice_date: month_start..month_end })
# puts "CGST out: #{inv_items.sum(:cgst_amount)}"
# puts "SGST out: #{inv_items.sum(:sgst_amount)}"
# puts "IGST out: #{inv_items.sum(:igst_amount)}"
# puts "Total out: #{inv_items.sum(:tax_amount)}"
