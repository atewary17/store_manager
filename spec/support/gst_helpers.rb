# spec/support/gst_helpers.rb
#
# Shared helpers for building GST test scenarios.
# Include in specs with: include GstHelpers

module GstHelpers
  # Build and confirm a purchase invoice in one call.
  # Returns the confirmed PurchaseInvoice.
  #
  # Usage:
  #   inv = confirmed_purchase(org, supplier, user, items: [
  #     { product: p1, qty: 10, total: 11800 },  # 18% GST included
  #   ])
  def confirmed_purchase(organisation, supplier, user, items:, date: Date.today)
    invoice = PurchaseInvoice.create!(
      organisation:  organisation,
      supplier:      supplier,
      user:          user,
      invoice_date:  date,
      delivery_date: date + 7,
      status:        'draft',
      total_amount:  0,
      total_taxable_amount: 0,
      total_tax_amount:     0
    )

    items.each do |item_attrs|
      PurchaseInvoiceItem.create!(
        purchase_invoice: invoice,
        product:          item_attrs[:product],
        quantity:         item_attrs[:qty] || 1,
        unit_rate:        0,
        total_amount:     item_attrs[:total],
        gst_rate:         0,
        taxable_amount:   0,
        tax_amount:       0,
        discount_percent: item_attrs[:discount_percent] || 0,
        discount_amount:  0,
        supply_type:      'intra_state',
        cgst_amount:      0,
        sgst_amount:      0,
        igst_amount:      0,
        metadata:         {}
      )
    end

    invoice.confirm!
    invoice.reload
    invoice
  end

  # Build and confirm a sales invoice in one call.
  # metadata must include cgst_percent and sgst_percent.
  def confirmed_sale(organisation, customer, user, items:, date: Date.today)
    invoice = SalesInvoice.create!(
      organisation:  organisation,
      customer:      customer,
      user:          user,
      invoice_date:  date,
      status:        'draft',
      total_amount:  0,
      total_taxable_amount: 0,
      total_tax_amount:     0
    )

    items.each do |item_attrs|
      SalesInvoiceItem.create!(
        sales_invoice:   invoice,
        product:         item_attrs[:product],
        line_type:       'product',
        quantity:        item_attrs[:qty] || 1,
        total_amount:    item_attrs[:total],
        discount_percent: item_attrs[:discount_percent] || 0,
        metadata: {
          'cgst_percent' => item_attrs[:cgst_percent] || 9.0,
          'sgst_percent' => item_attrs[:sgst_percent] || 9.0
        }
      )
    end

    result = invoice.confirm!(user)
    raise "Confirm failed: #{result[:errors]}" if result[:errors]&.any?
    invoice.reload
    invoice
  end

  # Shorthand: taxable from an inclusive-GST total
  def taxable(total_incl_gst, rate)
    (total_incl_gst / (1 + rate / 100.0)).round(2)
  end

  def tax(total_incl_gst, rate)
    total_incl_gst.round(2) - taxable(total_incl_gst, rate)
  end
end

RSpec.configure do |config|
  config.include GstHelpers, :gst
end
