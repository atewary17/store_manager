class ProductReviewMailer < ApplicationMailer
  TO  = 'subhasishr7@gmail.com'
  CC  = 'atewary17@gmail.com'

  # Called after PurchaseInvoice#confirm! when new unmatched products are created.
  # products      – Array of Product records (all under_review)
  # organisation  – Organisation that uploaded the invoice
  # purchase_invoice – the PurchaseInvoice these items came from
  def new_unmatched_products(products:, organisation:, purchase_invoice:)
    @products         = products.compact
    @organisation     = organisation
    @purchase_invoice = purchase_invoice
    @count            = @products.size
    @review_url       = admin_product_reviews_url

    mail(
      to:      TO,
      cc:      CC,
      subject: "Urgent: #{@count} New Product#{'s' if @count != 1} Pending Review — Action Required"
    )
  end
end
