# app/helpers/application_helper.rb
module ApplicationHelper

  # ── Dashboard shortcut catalog ─────────────────────────────────────────────
  # Each entry: key (stored in preferences), label, path, group, color
  SHORTCUT_CATALOG = [
    { key: 'new_sales_invoice',    label: 'New Sales Invoice',    path: '/sales/sales_invoices/new',          group: 'Sales',      color: 'teal'   },
    { key: 'sales_invoices',       label: 'Sales Invoices',       path: '/sales/sales_invoices',              group: 'Sales',      color: 'teal'   },
    { key: 'accounts_receivable',  label: 'Accounts Receivable',  path: '/sales/accounts_receivable',         group: 'Sales',      color: 'teal'   },
    { key: 'new_purchase_invoice', label: 'New Purchase Invoice', path: '/purchasing/purchase_invoices/new',  group: 'Purchasing', color: 'amber'  },
    { key: 'purchase_invoices',    label: 'Purchase Invoices',    path: '/purchasing/purchase_invoices',      group: 'Purchasing', color: 'amber'  },
    { key: 'accounts_payable',     label: 'Accounts Payable',     path: '/purchasing/accounts_payable',       group: 'Purchasing', color: 'amber'  },
    { key: 'digitise',             label: 'Digitise Invoice',     path: '/purchasing/digitise/new',           group: 'Purchasing', color: 'purple' },
    { key: 'customers',            label: 'Customers',            path: '/customers',                         group: 'Contacts',   color: 'blue'   },
    { key: 'new_customer',         label: 'New Customer',         path: '/customers/new',                     group: 'Contacts',   color: 'blue'   },
    { key: 'suppliers',            label: 'Suppliers',            path: '/purchasing/suppliers',              group: 'Contacts',   color: 'blue'   },
    { key: 'new_supplier',         label: 'New Supplier',         path: '/purchasing/suppliers/new',          group: 'Contacts',   color: 'blue'   },
    { key: 'products',             label: 'Products',             path: '/setup/products',                    group: 'Inventory',  color: 'purple' },
    { key: 'stock_levels',         label: 'Stock Levels',         path: '/inventory/stock_levels',            group: 'Inventory',  color: 'purple' },
    { key: 'sales_reports',        label: 'Sales Reports',        path: '/reports/sales',                     group: 'Reports',    color: 'red'    },
    { key: 'purchase_reports',     label: 'Purchase Reports',     path: '/reports/purchases',                 group: 'Reports',    color: 'red'    },
    { key: 'stock_reports',        label: 'Stock Reports',        path: '/reports/stock_reports',             group: 'Reports',    color: 'red'    },
    { key: 'cash_flow',            label: 'Cash Flow',            path: '/reports/cash_flows',                group: 'Reports',    color: 'red'    },
    { key: 'gst_reports',          label: 'GST Reports',          path: '/accounting/gst',                    group: 'Accounting', color: 'amber'  },
  ].freeze

  SHORTCUT_CATALOG_BY_KEY = SHORTCUT_CATALOG.index_by { |m| m[:key] }.freeze

  BRAND_HEX_MAP = {
    'asian paints' => '#e31837',
    'berger'       => '#0057a8',
    'birla opus'   => '#6d2b8f',
    'salimar'      => '#f47920',
  }.freeze

  # Returns a hex colour string for a brand, falling back to accent colour
  def brand_hex(brand)
    key = brand.name.to_s.downcase
    BRAND_HEX_MAP.each { |k, v| return v if key.include?(k) }
    '#4f8ef7'
  end
  # Converts a numeric amount to Indian currency words
  # e.g. 82200.00 → "INR Eighty Two Thousand Two Hundred Only"
  def amount_in_words(amount)
    ones = %w[Zero One Two Three Four Five Six Seven Eight Nine Ten Eleven Twelve
              Thirteen Fourteen Fifteen Sixteen Seventeen Eighteen Nineteen]
    tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety']

    two_d   = ->(n) { n < 20 ? ones[n] : tens[n / 10] + (n % 10 > 0 ? " #{ones[n % 10]}" : '') }
    three_d = ->(n) { n < 100 ? two_d.(n) : "#{ones[n / 100]} Hundred#{n % 100 > 0 ? " #{two_d.(n % 100)}" : ''}" }

    rupees = amount.to_f.round(2).to_i
    paise  = ((amount.to_f.round(2) - rupees) * 100).round
    return 'Zero Rupees Only' if rupees.zero? && paise.zero?

    r, parts = rupees, []
    parts << "#{three_d.(r / 10_000_000)} Crore" and r %= 10_000_000 if r >= 10_000_000
    parts << "#{two_d.(r / 100_000)} Lakh"       and r %= 100_000    if r >= 100_000
    parts << "#{two_d.(r / 1_000)} Thousand"      and r %= 1_000      if r >= 1_000
    parts << three_d.(r) if r > 0

    result = "INR #{parts.join(' ')} Only"
    result += " and #{two_d.(paise)} Paise" if paise > 0
    result
  end

  def status_badge_class(status)
    case status.to_s
    when 'done'       then 'badge-active'
    when 'processing' then 'badge-plan'
    when 'pending'    then 'badge-inactive'
    when 'failed'     then 'badge-inactive'
    else 'badge-inactive'
    end
  end
end