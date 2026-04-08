# db/seeds.rb
# Run with: rails db:seed
# Safe to re-run — all records use find_or_create_by! so nothing is duplicated.

puts "\n🌱 Seeding MyStoreManager database...\n"

# ══════════════════════════════════════════════════════════════════════════════
# ORGANISATION
# ══════════════════════════════════════════════════════════════════════════════
org = Organisation.find_or_create_by!(name: "Sharma Hardware & Paints Pvt Ltd") do |o|
  o.gst_number        = "19ABCPS1234C1ZX"
  o.gstin             = "19ABCPS1234C1ZX"
  o.pan               = "ABCPS1234C"
  o.state             = "West Bengal"
  o.state_code        = "19"
  o.address           = "12 Park Street, Kolkata, West Bengal - 700016"
  o.subscription_plan = "pro"
  o.status            = :active
end
puts "✅  Organisation : #{org.name} (ID: #{org.id})"

# ══════════════════════════════════════════════════════════════════════════════
# USER (owner)
# ══════════════════════════════════════════════════════════════════════════════
user = User.find_or_create_by!(email: "atewary17@gmail.com") do |u|
  u.first_name            = "Anish"
  u.last_name             = "Tewary"
  u.password              = "asansol8"
  u.password_confirmation = "asansol8"
  u.role                  = :super_admin
  u.status                = :active
  u.organisation          = org
end
# Ensure jti is set (needed for JWT API auth)
user.update_column(:jti, SecureRandom.hex(24)) if user.respond_to?(:jti) && user.jti.blank?
puts "✅  User          : #{user.full_name} <#{user.email}> — #{user.role}"

# ══════════════════════════════════════════════════════════════════════════════
# UNITS OF MEASURE
# ══════════════════════════════════════════════════════════════════════════════
uom_pcs = Uom.find_or_create_by!(short_name: "Pcs") do |u|
  u.name   = "Pieces"
  u.active = true
end

uom_tin = Uom.find_or_create_by!(short_name: "Tin") do |u|
  u.name   = "Tin"
  u.active = true
end

uom_ltr = Uom.find_or_create_by!(short_name: "Ltr") do |u|
  u.name   = "Litre"
  u.active = true
end

uom_kg = Uom.find_or_create_by!(short_name: "Kg") do |u|
  u.name   = "Kilogram"
  u.active = true
end

puts "✅  UOMs          : #{Uom.count} total (Pcs, Tin, Ltr, Kg)"

# ══════════════════════════════════════════════════════════════════════════════
# PRODUCT CATEGORY
# ══════════════════════════════════════════════════════════════════════════════
cat_paints = ProductCategory.find_or_create_by!(name: "Paints") do |c|
  c.description = "All types of paint products — enamel, emulsion, primer, distemper"
  c.active      = true
end

cat_hardware = ProductCategory.find_or_create_by!(name: "Hardware") do |c|
  c.description = "Hardware items — fasteners, fittings, tools"
  c.active      = true
end

puts "✅  Categories    : Paints, Hardware"

# Link categories to this organisation via join table
[cat_paints, cat_hardware].each do |cat|
  OrganisationProductCategory.find_or_create_by!(organisation: org, product_category: cat)
rescue => e
  # If model name differs, fall back to the association
  org.product_categories << cat unless org.product_categories.include?(cat) rescue nil
end

# ══════════════════════════════════════════════════════════════════════════════
# BRAND
# ══════════════════════════════════════════════════════════════════════════════
brand_ap = Brand.find_or_create_by!(name: "Asian Paints") do |b|
  b.short_name  = "AP"
  b.description = "Asian Paints Limited — India's largest paint company"
  b.active      = true
end

puts "✅  Brand         : Asian Paints (AP)"

# ══════════════════════════════════════════════════════════════════════════════
# PRODUCTS (10 products from your actual DB)
# All: category=Paints, brand=Asian Paints, UOM=Pcs, GST 18%, HSN 320890
# ══════════════════════════════════════════════════════════════════════════════
products_data = [
  { material_code: "00010210210", pack_code: "210", description: "AP APCO GLS ENML CAS GRN 1 LT",      mrp: 290.00 },
  { material_code: "00010506210", pack_code: "210", description: "AP APCO GLS ENML DPORANGE 1 LT",      mrp: 290.00 },
  { material_code: "00010616210", pack_code: "210", description: "AP APCO GLS ENML SM GREY 1 LT",       mrp: 262.00 },
  { material_code: "00014284210", pack_code: "210", description: "AP APCO GLS ENML DP MHGNY 1 LTR",    mrp: 290.00 },
  { material_code: "0001M003050", pack_code: "050", description: "AP APCO GLS ENML GOLD 50 ML",         mrp: 125.00 },
  { material_code: "0001M003120", pack_code: "120", description: "AP APCO GLS ENML GOLD 200 ML",        mrp: 390.00 },
  { material_code: "00070908150", pack_code: "150", description: "AP WOOD PRIMER WHITE 500ML",           mrp: 215.00 },
  { material_code: "00010125120", pack_code: "120", description: "AP APCO GLS ENML SKY BLUE 200ML",     mrp: nil    },
  { material_code: "00010119050", pack_code: "050", description: "AP APCO GLS ENML OX BLUE 50 ML",     mrp: nil    },
  { material_code: "00010119110", pack_code: "110", description: "AP APCO GLS ENML OX BLUE 100ML",     mrp: nil    },
]

products_data.each do |pd|
  # Products are shared across orgs — no direct organisation column.
  # They are linked via the organisation_products join table.
  product = Product.find_or_create_by!(material_code: pd[:material_code]) do |p|
    p.product_category = cat_paints
    p.base_uom         = uom_pcs
    p.brand            = brand_ap
    p.pack_code        = pd[:pack_code]
    p.description      = pd[:description]
    p.hsn_code         = "320890"
    p.gst_rate         = 18.00
    p.mrp              = pd[:mrp]
    p.active           = true
    p.metadata         = {}
  end

  # Enrol in org catalogue via organisation_products join table
  OrganisationProduct.find_or_create_by!(organisation: org, product: product)
end

puts "✅  Products      : #{products_data.size} products created/found"

# ══════════════════════════════════════════════════════════════════════════════
# SUPPLIER — Asian Paints Limited
# ══════════════════════════════════════════════════════════════════════════════
supplier = Supplier.find_or_create_by!(
  organisation: org,
  gstin:        "19AAACA3622K1ZS"
) do |s|
  s.name       = "Asian Paints Limited"
  s.pan        = "AAACA3622K"
  s.state      = "West Bengal"
  s.state_code = "19"
  s.active     = true
  s.metadata   = {
    "address"       => "Belur Math Road, Howrah, West Bengal - 711202",
    "phone"         => "033-26688888",
    "email"         => "trade@asianpaints.com",
    "credit_days"   => 30,
    "delivery_note" => "WB Regional Depot"
  }
end
puts "✅  Supplier      : #{supplier.name} (GSTIN: #{supplier.gstin})"

# ══════════════════════════════════════════════════════════════════════════════
# CUSTOMER — Local trade customer
# ══════════════════════════════════════════════════════════════════════════════
customer = Customer.find_or_create_by!(
  organisation: org,
  name:         "Kolkata Hardware & Civil Supplies"
) do |c|
  c.gstin      = "19AABCK1234A1ZP"
  c.pan        = "AABCK1234A"
  c.state      = "West Bengal"
  c.state_code = "19"
  c.phone      = "9830012345"
  c.active     = true
  c.metadata   = {
    "address"       => "45 B.B. Ganguly Street, Kolkata - 700012",
    "email"         => "procurement@kolkatahardware.com",
    "credit_limit"  => 50000,
    "credit_days"   => 15,
    "contact_person"=> "Ramesh Agarwal"
  }
end
puts "✅  Customer (B2B): #{customer.name} (GSTIN: #{customer.gstin})"

# Walk-in customer (no GSTIN — B2C)
walkin = Customer.find_or_create_by!(
  organisation: org,
  name:         "Walk-in Customer"
) do |c|
  c.state      = "West Bengal"
  c.state_code = "19"
  c.active     = true
  c.metadata   = {}
end
puts "✅  Customer (B2C): #{walkin.name}"

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
puts "\n" + "═" * 52
puts "  Seeding complete — MyStoreManager"
puts "═" * 52
puts "  Organisation : #{org.name}"
puts "  State        : #{org.state} (Code #{org.state_code})"
puts "  GSTIN        : #{org.gst_number}"
puts "  PAN          : #{org.pan}"
puts "  ─────────────────────────────────────────────"
puts "  Login email  : #{user.email}"
puts "  Password     : asansol8"
puts "  Role         : #{user.role}"
puts "  ─────────────────────────────────────────────"
puts "  UOMs         : #{Uom.count}"
puts "  Categories   : #{ProductCategory.count}"
puts "  Brands       : #{Brand.count}"
puts "  Products     : #{OrganisationProduct.where(organisation: org).count}"
puts "  Suppliers    : #{Supplier.where(organisation: org).count}"
puts "  Customers    : #{Customer.where(organisation: org).count}"
puts "═" * 52
puts "\n  Run: rails db:seed"
puts "  API: POST /api/v1/auth/login\n\n"