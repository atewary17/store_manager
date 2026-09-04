# Add a Supplier

Create a supplier once, then pick them on every bill you enter.

## Fields
- **Name** *(required)* — the supplier's business name, as it appears on
  their bills.
- **GSTIN** — their 15-character GST number. Needed for your GST returns and
  for claiming input tax credit.
- **PAN** — their 10-character PAN.
- **State** and **State Code** — **this matters.** It decides how GST is
  charged on their bills:
  - Same state as you → **CGST + SGST**
  - Different state → **IGST**
- **Address** — used on printed documents.

> Tip: get the GSTIN and state right the first time. If they are wrong, the
> GST on every bill from this supplier will be wrong too.
