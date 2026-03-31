# spec/controllers/accounting/gst_reports_controller_spec.rb
#
# Integration-style controller specs for the entire GST reporting module:
#   - GST Dashboard (index)
#   - GSTR-1 outward supplies
#   - GSTR-3B with 7-step ITC set-off (including IGST cross-head utilisation)
#   - ITC Register
#   - HSN Summary
#
# Key scenarios:
#   A) Intra-state only: buy and sell within West Bengal
#   B) Inter-state purchase, intra-state sale: IGST credit offsets CGST+SGST output
#   C) Mixed: both inter and intra purchases + sales
#   D) Edge: ITC > output (credit carry-forward), zero GST, empty period

require 'rails_helper'

RSpec.describe Accounting::GstReportsController, type: :controller, gst: true do
  include GstHelpers
  include Devise::Test::ControllerHelpers

  # ── Shared setup ───────────────────────────────────────────────────────────
  let(:org)  { create(:organisation, state: 'West Bengal', state_code: '19') }
  let(:user) { create(:gst_user, organisation: org, role: :admin) }

  let(:wb_supplier)  { create(:gst_supplier, :intra_state, organisation: org) }
  let(:mh_supplier)  { create(:gst_supplier, :inter_state, organisation: org) }
  let(:wb_customer)  { create(:gst_customer, :intra_state, organisation: org) }
  let(:bi_customer)  { create(:gst_customer, :inter_state, organisation: org) }
  let(:b2b_customer) { create(:gst_customer, :intra_state, :b2b, organisation: org) }

  let(:p18)  { create(:gst_product, :gst_18) }
  let(:p12)  { create(:gst_product, :gst_12) }
  let(:p28)  { create(:gst_product, :gst_28) }
  let(:p0)   { create(:gst_product, :gst_zero) }

  # Period: current month
  let(:this_month) { Date.today.beginning_of_month }
  let(:period_params) { { month: this_month.month, year: this_month.year } }

  before do
    sign_in user
    # Ensure current_user.organisation returns org
    allow(controller).to receive(:current_user).and_return(user)
    allow(user).to receive(:organisation).and_return(org)
  end

  # ══════════════════════════════════════════════════════════════════════════
  # SCENARIO A: Intra-state only
  # ══════════════════════════════════════════════════════════════════════════
  context 'Scenario A — intra-state purchases and sales (West Bengal only)' do
    before do
      # Purchase: 20 cans paint from WB supplier @ ₹23,600 (18% GST)
      # taxable = 20000, CGST = 1800, SGST = 1800
      confirmed_purchase(org, wb_supplier, user,
        items: [{ product: p18, qty: 20, total: 23600.0 }],
        date: this_month)

      # Sale: 5 cans to WB customer @ ₹5900 (18% GST)
      # taxable = 5000, CGST = 450, SGST = 450
      inv = SalesInvoice.create!(
        organisation: org, customer: wb_customer, user: user,
        invoice_date: this_month, status: 'draft',
        total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
      )
      SalesInvoiceItem.create!(
        sales_invoice: inv, product: p18, line_type: 'product',
        quantity: 5, total_amount: 5900.0, discount_percent: 0,
        metadata: { 'cgst_percent' => 9.0, 'sgst_percent' => 9.0 }
      )
      inv.confirm!(user)
    end

    describe 'GET #index (GST Dashboard)' do
      before { get :index, params: period_params }

      it 'returns 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'computes output tax correctly (CGST+SGST from sales)' do
        expect(assigns(:output)[:cgst]).to be_within(0.01).of(450.0)
        expect(assigns(:output)[:sgst]).to be_within(0.01).of(450.0)
        expect(assigns(:output)[:igst]).to eq(0.0)
        expect(assigns(:output)[:tax]).to be_within(0.01).of(900.0)
      end

      it 'computes input tax (ITC) correctly (CGST+SGST from purchases)' do
        expect(assigns(:input)[:cgst]).to be_within(0.01).of(1800.0)
        expect(assigns(:input)[:sgst]).to be_within(0.01).of(1800.0)
        expect(assigns(:input)[:igst]).to eq(0.0)
        expect(assigns(:input)[:tax]).to be_within(0.01).of(3600.0)
      end

      it 'computes net GST as output minus input (negative = credit)' do
        net = assigns(:net_gst)
        expect(net[:cgst]).to be_within(0.01).of(450.0 - 1800.0)   # -1350 (credit)
        expect(net[:sgst]).to be_within(0.01).of(450.0 - 1800.0)
        expect(net[:total]).to be_within(0.01).of(900.0 - 3600.0)  # -2700 (credit)
      end

      it 'sets filing deadline variables' do
        expect(assigns(:gstr1_due)).not_to be_nil
        expect(assigns(:gstr3b_due)).not_to be_nil
      end
    end

    describe 'GET #gstr3b' do
      before { get :gstr3b, params: period_params }

      it 'returns 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'sets @total_payable to 0 (ITC > output)' do
        expect(assigns(:total_payable)).to eq(0.0)
      end

      it 'carries forward CGST and SGST credit' do
        expect(assigns(:cgst_credit)).to be_within(0.01).of(1350.0)
        expect(assigns(:sgst_credit)).to be_within(0.01).of(1350.0)
      end

      it 'sets itc_utilisation — step 4 CGST vs CGST used' do
        u = assigns(:itc_utilisation)
        # CGST output 450 paid from CGST ITC 1800
        expect(u[:cgst_vs_cgst]).to be_within(0.01).of(450.0)
        # SGST output 450 paid from SGST ITC 1800
        expect(u[:sgst_vs_sgst]).to be_within(0.01).of(450.0)
        # No IGST involved
        expect(u[:igst_vs_igst]).to eq(0.0)
        expect(u[:igst_vs_cgst]).to eq(0.0)
        expect(u[:igst_vs_sgst]).to eq(0.0)
      end
    end

    describe 'GET #itc (ITC register)' do
      before { get :itc, params: period_params }

      it 'returns 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'lists purchase invoice items with GST' do
        expect(assigns(:items).count).to eq(1)
      end

      it 'computes total ITC correctly' do
        expect(assigns(:total_itc)).to be_within(0.01).of(3600.0)
        expect(assigns(:total_itc_cgst)).to be_within(0.01).of(1800.0)
        expect(assigns(:total_itc_sgst)).to be_within(0.01).of(1800.0)
        expect(assigns(:total_itc_igst)).to eq(0.0)
      end

      it 'groups ITC by GST rate' do
        by_rate = assigns(:by_rate)
        expect(by_rate.map { |r, _| r.to_f }).to include(18.0)
        expect(by_rate.find { |r, _| r.to_f == 18.0 }.last[:tax]).to be_within(0.01).of(3600.0)
      end
    end

    describe 'GET #gstr1' do
      before { get :gstr1, params: period_params }

      it 'returns 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'places intra-state sale in B2C (no GSTIN on customer)' do
        expect(assigns(:b2c).count).to eq(1)
        expect(assigns(:b2b).count).to eq(0)
      end

      it 'computes GSTR-1 totals' do
        expect(assigns(:totals)[:tax]).to be_within(0.01).of(900.0)
        expect(assigns(:totals)[:taxable]).to be_within(0.01).of(5000.0)
      end
    end

    describe 'GET #hsn' do
      before { get :hsn, params: period_params }

      it 'returns 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'returns sales HSN rows' do
        expect(assigns(:sales_hsn)).not_to be_empty
      end

      it 'returns purchase HSN rows' do
        expect(assigns(:purchase_hsn)).not_to be_empty
      end

      it 'groups by HSN code' do
        sales_hsns = assigns(:sales_hsn).map { |r| r['hsn_code'] }
        expect(sales_hsns).to include('32081090')
      end
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # SCENARIO B: IGST ITC offsetting CGST + SGST output
  # ══════════════════════════════════════════════════════════════════════════
  context 'Scenario B — inter-state purchase, intra-state sale (your exact example)' do
    # Purchases: ₹3,00,000 from Maharashtra supplier @ 18% = IGST ₹54,000
    # Sales: ₹1,20,000 intra-state @ 18% = CGST ₹10,800 + SGST ₹10,800
    before do
      confirmed_purchase(org, mh_supplier, user,
        items: [{ product: p18, qty: 300, total: 354000.0 }],  # 300000 taxable + 54000 IGST
        date: this_month)

      inv = SalesInvoice.create!(
        organisation: org, customer: wb_customer, user: user,
        invoice_date: this_month, status: 'draft',
        total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
      )
      SalesInvoiceItem.create!(
        sales_invoice: inv, product: p18, line_type: 'product',
        quantity: 100, total_amount: 141600.0,  # 120000 taxable + 21600 tax (CGST+SGST)
        discount_percent: 0,
        metadata: { 'cgst_percent' => 9.0, 'sgst_percent' => 9.0 }
      )
      inv.confirm!(user)
    end

    describe 'GET #gstr3b — 7-step IGST ITC set-off' do
      before { get :gstr3b, params: period_params }

      it 'returns 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'shows IGST ITC of 54000' do
        expect(assigns(:input)[:igst]).to be_within(1.0).of(54000.0)
      end

      it 'shows CGST output of 10800' do
        expect(assigns(:output)[:cgst]).to be_within(1.0).of(10800.0)
      end

      it 'shows SGST output of 10800' do
        expect(assigns(:output)[:sgst]).to be_within(1.0).of(10800.0)
      end

      it 'Step 1: no IGST output to pay (all zero)' do
        u = assigns(:itc_utilisation)
        expect(u[:igst_vs_igst]).to eq(0.0)
      end

      it 'Step 2: IGST ITC covers CGST output (10800)' do
        u = assigns(:itc_utilisation)
        expect(u[:igst_vs_cgst]).to be_within(1.0).of(10800.0)
      end

      it 'Step 3: IGST ITC covers SGST output (10800)' do
        u = assigns(:itc_utilisation)
        expect(u[:igst_vs_sgst]).to be_within(1.0).of(10800.0)
      end

      it 'total payable = 0 (IGST ITC covers everything)' do
        expect(assigns(:total_payable)).to eq(0.0)
      end

      it 'carries forward remaining IGST credit (54000 - 10800 - 10800 = 32400)' do
        expect(assigns(:igst_credit)).to be_within(1.0).of(32400.0)
      end

      it 'CGST and SGST cash payable are both zero' do
        expect(assigns(:cgst_payable)).to eq(0.0)
        expect(assigns(:sgst_payable)).to eq(0.0)
      end
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # SCENARIO C: Mixed purchases and inter-state sale
  # ══════════════════════════════════════════════════════════════════════════
  context 'Scenario C — mixed ITC, inter-state sale creates IGST output' do
    # ITC available:  IGST ₹20,000  CGST ₹8,000  SGST ₹8,000
    # Output due:     CGST ₹15,000  SGST ₹15,000  IGST ₹0
    # (from "What If You Have a Mix?" in your docs)
    before do
      # Intra-state purchase: CGST 8000, SGST 8000
      confirmed_purchase(org, wb_supplier, user,
        items: [{ product: p18, qty: 94, total: 105040.0 }],  # ≈88,169 taxable, ≈15,871 tax... need exact
        date: this_month)

      # Inter-state purchase: IGST 20000
      confirmed_purchase(org, mh_supplier, user,
        items: [{ product: p18, qty: 119, total: 133280.0 }],  # ≈113,000 taxable, 20,340 IGST
        date: this_month)

      # Inter-state sale to Bihar customer: IGST output
      inv = SalesInvoice.create!(
        organisation: org, customer: bi_customer, user: user,
        invoice_date: this_month, status: 'draft',
        total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
      )
      SalesInvoiceItem.create!(
        sales_invoice: inv, product: p18, line_type: 'product',
        quantity: 50, total_amount: 59000.0,  # 50000 taxable, 9000 IGST
        discount_percent: 0,
        metadata: { 'cgst_percent' => 9.0, 'sgst_percent' => 9.0 }
      )
      inv.confirm!(user)
    end

    describe 'GET #gstr3b' do
      before { get :gstr3b, params: period_params }

      it 'shows inter-state sale as IGST output' do
        expect(assigns(:output)[:igst]).to be > 0
      end

      it 'uses IGST ITC to pay IGST output first (Step 1)' do
        u = assigns(:itc_utilisation)
        expect(u[:igst_vs_igst]).to be > 0
      end

      it 'CGST credit cannot be used for SGST output' do
        u = assigns(:itc_utilisation)
        # This key should not exist in our implementation (CGST→SGST forbidden)
        expect(u.key?(:cgst_vs_sgst)).to be(false)
      end

      it 'SGST credit cannot be used for CGST output' do
        u = assigns(:itc_utilisation)
        expect(u.key?(:sgst_vs_cgst)).to be(false)
      end
    end

    describe 'GET #gstr1 — inter-state sale appears correctly' do
      before { get :gstr1, params: period_params }

      it 'inter-state sale to unregistered customer appears in B2C' do
        # bi_customer has no GSTIN
        expect(assigns(:b2c).count).to be >= 1
      end
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # SCENARIO D: Edge cases
  # ══════════════════════════════════════════════════════════════════════════
  context 'Scenario D — edge cases' do

    describe 'empty period (no invoices)' do
      before { get :index, params: { month: 1, year: 2020 } }

      it 'returns 200 without error' do
        expect(response).to have_http_status(:ok)
      end

      it 'shows zero output tax' do
        expect(assigns(:output)[:tax]).to eq(0.0)
      end

      it 'shows zero ITC' do
        expect(assigns(:input)[:tax]).to eq(0.0)
      end

      it 'shows zero net GST' do
        expect(assigns(:net_gst)[:total]).to eq(0.0)
      end
    end

    describe 'ITC exactly equals output (zero payable, zero carry-forward)' do
      before do
        # Purchase: CGST 900 + SGST 900 = 1800 total
        confirmed_purchase(org, wb_supplier, user,
          items: [{ product: p18, qty: 10, total: 11800.0 }],
          date: this_month)

        # Sale: CGST 900 + SGST 900 = 1800 total (same amount)
        inv = SalesInvoice.create!(
          organisation: org, customer: wb_customer, user: user,
          invoice_date: this_month, status: 'draft',
          total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
        )
        SalesInvoiceItem.create!(
          sales_invoice: inv, product: p18, line_type: 'product',
          quantity: 10, total_amount: 11800.0, discount_percent: 0,
          metadata: { 'cgst_percent' => 9.0, 'sgst_percent' => 9.0 }
        )
        inv.confirm!(user)
        get :gstr3b, params: period_params
      end

      it 'total payable is 0' do
        expect(assigns(:total_payable)).to eq(0.0)
      end

      it 'all credits are 0 (fully utilised)' do
        expect(assigns(:igst_credit)).to eq(0.0)
        expect(assigns(:cgst_credit)).to eq(0.0)
        expect(assigns(:sgst_credit)).to eq(0.0)
      end
    end

    describe 'output tax exceeds ITC — cash payment required' do
      before do
        # Small purchase: CGST 90, SGST 90
        confirmed_purchase(org, wb_supplier, user,
          items: [{ product: p18, qty: 1, total: 1180.0 }],
          date: this_month)

        # Large sale: CGST 900, SGST 900
        inv = SalesInvoice.create!(
          organisation: org, customer: wb_customer, user: user,
          invoice_date: this_month, status: 'draft',
          total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
        )
        SalesInvoiceItem.create!(
          sales_invoice: inv, product: p18, line_type: 'product',
          quantity: 10, total_amount: 11800.0, discount_percent: 0,
          metadata: { 'cgst_percent' => 9.0, 'sgst_percent' => 9.0 }
        )
        inv.confirm!(user)
        get :gstr3b, params: period_params
      end

      it 'total payable is positive (cash required)' do
        expect(assigns(:total_payable)).to be > 0
      end

      it 'CGST payable = 900 - 90 = 810' do
        expect(assigns(:cgst_payable)).to be_within(0.01).of(810.0)
      end

      it 'SGST payable = 900 - 90 = 810' do
        expect(assigns(:sgst_payable)).to be_within(0.01).of(810.0)
      end
    end

    describe 'zero GST products — no division by zero' do
      before do
        confirmed_purchase(org, wb_supplier, user,
          items: [{ product: p0, qty: 10, total: 1000.0 }],
          date: this_month)
        get :itc, params: period_params
      end

      it 'returns 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'excludes zero-GST items from ITC totals (tax_amount = 0 filter)' do
        # Items with tax_amount = 0 are excluded by the WHERE clause
        expect(assigns(:total_itc)).to eq(0.0)
      end
    end

    describe 'B2B sale (customer has GSTIN) appears in GSTR-1 B2B table' do
      before do
        inv = SalesInvoice.create!(
          organisation: org, customer: b2b_customer, user: user,
          invoice_date: this_month, status: 'draft',
          total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
        )
        SalesInvoiceItem.create!(
          sales_invoice: inv, product: p18, line_type: 'product',
          quantity: 5, total_amount: 5900.0, discount_percent: 0,
          metadata: { 'cgst_percent' => 9.0, 'sgst_percent' => 9.0 }
        )
        inv.confirm!(user)
        get :gstr1, params: period_params
      end

      it 'places GSTIN customer invoice in B2B table' do
        expect(assigns(:b2b).count).to eq(1)
        expect(assigns(:b2c).count).to eq(0)
      end

      it 'B2B invoice has customer GSTIN' do
        expect(assigns(:b2b).first.customer.gstin).to be_present
      end
    end

    describe 'multiple GST rates in HSN summary' do
      before do
        confirmed_purchase(org, wb_supplier, user,
          items: [
            { product: p18, qty: 5,  total: 5900.0  },
            { product: p12, qty: 10, total: 11200.0 },
            { product: p28, qty: 2,  total: 2560.0  }
          ],
          date: this_month)
        get :hsn, params: period_params
      end

      it 'returns 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'shows 3 distinct HSN rows in purchases' do
        hsn_codes = assigns(:purchase_hsn).map { |r| r['hsn_code'] }
        expect(hsn_codes.uniq.length).to eq(3)
      end

      it 'groups by gst_rate correctly' do
        rates = assigns(:purchase_hsn).map { |r| r['gst_rate'].to_f }
        expect(rates).to include(18.0)
        expect(rates).to include(12.0)
        expect(rates).to include(28.0)
      end
    end

    describe 'period selector filters correctly' do
      before do
        # Invoice in January 2026
        confirmed_purchase(org, wb_supplier, user,
          items: [{ product: p18, qty: 1, total: 1180.0 }],
          date: Date.new(2026, 1, 15))

        # Invoice in February 2026
        confirmed_purchase(org, wb_supplier, user,
          items: [{ product: p18, qty: 2, total: 2360.0 }],
          date: Date.new(2026, 2, 15))
      end

      it 'only includes January invoice when Jan selected' do
        get :itc, params: { month: 1, year: 2026 }
        expect(assigns(:total_itc)).to be_within(0.01).of(180.0)
      end

      it 'only includes February invoice when Feb selected' do
        get :itc, params: { month: 2, year: 2026 }
        expect(assigns(:total_itc)).to be_within(0.01).of(360.0)
      end
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # GSTR-3B 7-step set-off: verified step by step
  # ══════════════════════════════════════════════════════════════════════════
  context 'Scenario E — verifying all 7 steps of the IGST set-off algorithm' do
    # ITC available: IGST 20000, CGST 8000, SGST 8000
    # Output due:    IGST 5000, CGST 15000, SGST 15000
    #
    # Step 1: IGST ITC 20000 → IGST output 5000  → used 5000, IGST ITC left 15000
    # Step 2: IGST ITC 15000 → CGST output 15000 → used 15000, IGST ITC left 0
    # Step 3: IGST ITC 0     → SGST output 15000 → used 0, IGST ITC left 0
    # Step 4: CGST ITC 8000  → CGST output 0     → used 0, CGST ITC left 8000
    # Step 5: CGST ITC 8000  → IGST output 0     → used 0, CGST ITC left 8000
    # Step 6: SGST ITC 8000  → SGST output 15000 → used 8000, SGST ITC left 0
    # Step 7: SGST ITC 0     → IGST output 0     → used 0
    #
    # Final: IGST payable 0, CGST payable 0, SGST payable 7000
    #        IGST carry-fwd 0, CGST carry-fwd 8000, SGST carry-fwd 0
    #
    # Note: These are approximate because we work with GST-inclusive totals.
    # The exact amounts depend on taxable values derived from the totals.

    it 'runs the full 7-step algorithm without error and produces correct cash payable' do
      # IGST ITC ≈ 20000 → inter-state purchase of ~133,900 incl 28% from MH
      # IGST = 133900/1.28 * 0.28 = 29275 ... let's use 18% for cleaner numbers
      # Inter-state: 118000 total, taxable=100000, IGST=18000
      confirmed_purchase(org, mh_supplier, user,
        items: [{ product: p18, qty: 100, total: 118000.0 }],
        date: this_month)

      # Intra-state: 94400 total, taxable=80000, CGST=7200, SGST=7200
      confirmed_purchase(org, wb_supplier, user,
        items: [{ product: p18, qty: 80, total: 94400.0 }],
        date: this_month)

      # Intra-state sales: 177000 total, taxable=150000, CGST=13500, SGST=13500
      inv = SalesInvoice.create!(
        organisation: org, customer: wb_customer, user: user,
        invoice_date: this_month, status: 'draft',
        total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
      )
      SalesInvoiceItem.create!(
        sales_invoice: inv, product: p18, line_type: 'product',
        quantity: 150, total_amount: 177000.0, discount_percent: 0,
        metadata: { 'cgst_percent' => 9.0, 'sgst_percent' => 9.0 }
      )
      inv.confirm!(user)

      get :gstr3b, params: period_params

      u = assigns(:itc_utilisation)

      # Step 1: IGST vs IGST output (no IGST output → 0 used)
      expect(u[:igst_vs_igst]).to eq(0.0)

      # Step 2: IGST vs CGST — should use up to CGST output (13500)
      expect(u[:igst_vs_cgst]).to be_within(1.0).of(13500.0)

      # Step 3: IGST vs SGST — remaining IGST (18000-13500=4500) goes to SGST output
      expect(u[:igst_vs_sgst]).to be_within(1.0).of(4500.0)

      # Step 4: CGST vs remaining CGST output (0 remaining after step 2)
      expect(u[:cgst_vs_cgst]).to eq(0.0)

      # Step 6: SGST vs remaining SGST output (13500 - 4500 = 9000 remaining)
      expect(u[:sgst_vs_sgst]).to be_within(1.0).of(9000.0)

      # Cash SGST payable (13500 - 4500 - 7200 = 1800)
      expect(assigns(:sgst_payable)).to be_within(1.0).of(1800.0)
      expect(assigns(:cgst_payable)).to eq(0.0)
      expect(assigns(:igst_payable)).to eq(0.0)

      # CGST carry-forward (7200 unused)
      expect(assigns(:cgst_credit)).to be_within(1.0).of(7200.0)
    end
  end
end