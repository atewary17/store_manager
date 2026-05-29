# db/seeds.rb
# Run with: rails db:seed
# Fully idempotent — safe to re-run on every deploy.
# Finds records by multiple keys before creating to avoid uniqueness conflicts.

puts "\n Seeding MyStoreManager database...\n"

# ══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════════════════

# Find a UOM by name OR short_name, then create or update it.
def seed_uom(name:, short_name:, aliases: [])
  record = Uom.find_by(name: name) || Uom.find_by(short_name: short_name)
  if record
    record.update_columns(
      name:       name,
      short_name: short_name,
      active:     true,
      aliases:    aliases
    )
  else
    Uom.create!(
      name:       name,
      short_name: short_name,
      active:     true,
      aliases:    aliases
    )
  end
rescue => e
  puts "  [WARN] UOM '#{name}' skipped: #{e.message}"
end

# Find a Brand by name OR short_name, then create or update it.
def seed_brand(name:, short_name:, aliases: [])
  record = Brand.find_by(name: name) || Brand.find_by(short_name: short_name)
  if record
    record.update_columns(
      name:       name,
      short_name: short_name,
      active:     true,
      aliases:    aliases
    )
  else
    Brand.create!(
      name:       name,
      short_name: short_name,
      active:     true,
      aliases:    aliases
    )
  end
rescue => e
  puts "  [WARN] Brand '#{name}' skipped: #{e.message}"
end

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
puts "  Organisation : #{org.name} (ID: #{org.id})"

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
user.update_column(:jti, SecureRandom.hex(24)) if user.respond_to?(:jti) && user.jti.blank?
puts "  User          : #{user.first_name} #{user.last_name} <#{user.email}> — #{user.role}"

# ══════════════════════════════════════════════════════════════════════════════
# UNITS OF MEASURE
# ══════════════════════════════════════════════════════════════════════════════
uom_data = [
  # ── Fallback ──────────────────────────────────────────────────────────────
  { name: "Others",        short_name: "OTH",  aliases: %w[other oth misc miscellaneous na n/a unknown] },

  # ── Count / discrete ──────────────────────────────────────────────────────
  { name: "Units",         short_name: "UNT",  aliases: %w[unit units unt nos no. nos. number numbers] },
  { name: "Pieces",        short_name: "Pcs",  aliases: %w[pcs pc piece piec each ea] },
  { name: "Numbers",       short_name: "Nos",  aliases: %w[no. num] },
  { name: "Pair",          short_name: "Pr",   aliases: %w[pair pairs pr] },
  { name: "Set",           short_name: "Set",  aliases: %w[set sets] },
  { name: "Box",           short_name: "Box",  aliases: %w[box boxes bx] },
  { name: "Carton",        short_name: "Ctn",  aliases: %w[ctn carton cartons ct] },
  { name: "Pack",          short_name: "Pkt",  aliases: %w[pkt pack packs packet packets pk pck] },
  { name: "Bundle",        short_name: "Bdl",  aliases: %w[bdl bundle bundles bndl] },
  { name: "Roll",          short_name: "Roll", aliases: %w[roll rolls rll rl] },
  { name: "Sheet",         short_name: "Sht",  aliases: %w[sht sheet sheets sh] },
  { name: "Bag",           short_name: "Bag",  aliases: %w[bag bags bg] },
  { name: "Drum",          short_name: "Drm",  aliases: %w[drm drum drums dr] },
  { name: "Can",           short_name: "Can",  aliases: %w[can cans] },
  { name: "Tin",           short_name: "Tin",  aliases: %w[tin tins tn] },
  { name: "Bottle",        short_name: "Btl",  aliases: %w[btl bottle bottles bot] },
  { name: "Tube",          short_name: "Tube", aliases: %w[tube tubes tub] },
  { name: "Coil",          short_name: "Coil", aliases: %w[coil coils] },
  { name: "Strip",         short_name: "Str",  aliases: %w[str strip strips] },
  { name: "Gross",         short_name: "Grs",  aliases: %w[grs gross] },
  { name: "Dozen",         short_name: "Doz",  aliases: %w[doz dozen dozens dz] },
  { name: "Ream",          short_name: "Ream", aliases: %w[ream reams rm] },

  # ── Weight ────────────────────────────────────────────────────────────────
  { name: "Kilogram",      short_name: "Kg",   aliases: %w[kg kgs kilogram kilograms kilo kilos] },
  { name: "Gram",          short_name: "Gm",   aliases: %w[gm gms gram grams g gr] },
  { name: "Milligram",     short_name: "Mg",   aliases: %w[mg milligram milligrams] },
  { name: "Quintal",       short_name: "Qtl",  aliases: %w[qtl quintal quintals q.] },
  { name: "Metric Ton",    short_name: "MT",   aliases: %w[mt m.t. metric ton metric tons tonne tonnes ton tons t] },

  # ── Volume / liquid ───────────────────────────────────────────────────────
  { name: "Litre",         short_name: "Ltr",  aliases: %w[ltr ltrs litre litres liter liters l lt] },
  { name: "Millilitre",    short_name: "ML",   aliases: %w[ml mls millilitre millilitres milliliter milliliters] },
  { name: "Kilolitre",     short_name: "KL",   aliases: %w[kl kilolitre kilolitres kiloliter kiloliters] },

  # ── Length / area ─────────────────────────────────────────────────────────
  { name: "Metre",         short_name: "Mtr",  aliases: %w[mtr mtrs metre metres meter meters m.] },
  { name: "Centimetre",    short_name: "Cm",   aliases: %w[cm cms centimetre centimetres centimeter centimeters] },
  { name: "Millimetre",    short_name: "Mm",   aliases: %w[mm mms millimetre millimetres millimeter millimeters] },
  { name: "Foot",          short_name: "Ft",   aliases: ["ft", "feet", "foot'"] },
  { name: "Inch",          short_name: "In",   aliases: ["in", "inch", 'inches"'] },
  { name: "Square Metre",  short_name: "Sqm",  aliases: %w[sqm sq.m sq m2 square metre square meter sqmt] },
  { name: "Square Foot",   short_name: "Sqft", aliases: %w[sqft sq.ft sq ft ft2 square foot square feet] },
  { name: "Running Metre", short_name: "Rmt",  aliases: %w[rmt rm r.mt running metre running meter r/m] },
]

uom_data.each do |d|
  seed_uom(name: d[:name], short_name: d[:short_name], aliases: d[:aliases])
end
puts "  UOMs          : #{Uom.count} total"

# ══════════════════════════════════════════════════════════════════════════════
# PRODUCT CATEGORIES
# ══════════════════════════════════════════════════════════════════════════════
category_data = [
  { name: "Paints", description: "All paint and coating products — enamel, emulsion, primer, distemper, texture", is_paint_type: true  },
  { name: "Others", description: "Uncategorised or non-paint products",                                            is_paint_type: false },
]

category_data.each do |d|
  cat = ProductCategory.find_or_create_by!(name: d[:name]) do |c|
    c.description   = d[:description]
    c.is_paint_type = d[:is_paint_type]
    c.active        = true
  end
  # Enrol in org — try join model first, fall back to association
  begin
    OrganisationProductCategory.find_or_create_by!(organisation: org, product_category: cat)
  rescue
    org.product_categories << cat unless org.product_categories.include?(cat) rescue nil
  end
end
puts "  Categories    : #{ProductCategory.count} total"

# ══════════════════════════════════════════════════════════════════════════════
# BRANDS
# ══════════════════════════════════════════════════════════════════════════════
brand_data = [
  { name: "Asian Paints",   short_name: "AP",  aliases: %w[asian ap asian-paints asianpaints a.p.] },
  { name: "Shalimar Paints", short_name: "SHL", aliases: %w[shalimar shl shalimar-paints salimar] },
  { name: "Duke Paints",    short_name: "DUK", aliases: %w[duke duk duke-paints] },
  { name: "Others",         short_name: "OTH", aliases: %w[other others misc unknown unbranded generic] },
]

brand_data.each do |d|
  seed_brand(name: d[:name], short_name: d[:short_name], aliases: d[:aliases])
end
puts "  Brands        : #{Brand.count} total"

# ══════════════════════════════════════════════════════════════════════════════
# PRODUCTS (Asian Paints enamel range)
# ══════════════════════════════════════════════════════════════════════════════
cat_paints = ProductCategory.find_by!(name: "Paints")
brand_ap   = Brand.find_by!(name: "Asian Paints")
uom_pcs    = Uom.find_by!(name: "Pieces")

products_data = [
  { material_code: "00010210210", pack_code: "210", description: "AP APCO GLS ENML CAS GRN 1 LT",   mrp: 290.00 },
  { material_code: "00010506210", pack_code: "210", description: "AP APCO GLS ENML DPORANGE 1 LT",  mrp: 290.00 },
  { material_code: "00010616210", pack_code: "210", description: "AP APCO GLS ENML SM GREY 1 LT",   mrp: 262.00 },
  { material_code: "00014284210", pack_code: "210", description: "AP APCO GLS ENML DP MHGNY 1 LTR", mrp: 290.00 },
  { material_code: "0001M003050", pack_code: "050", description: "AP APCO GLS ENML GOLD 50 ML",      mrp: 125.00 },
  { material_code: "0001M003120", pack_code: "120", description: "AP APCO GLS ENML GOLD 200 ML",     mrp: 390.00 },
  { material_code: "00070908150", pack_code: "150", description: "AP WOOD PRIMER WHITE 500ML",        mrp: 215.00 },
  { material_code: "00010125120", pack_code: "120", description: "AP APCO GLS ENML SKY BLUE 200ML",  mrp: nil    },
  { material_code: "00010119050", pack_code: "050", description: "AP APCO GLS ENML OX BLUE 50 ML",   mrp: nil    },
  { material_code: "00010119110", pack_code: "110", description: "AP APCO GLS ENML OX BLUE 100ML",   mrp: nil    },
]

products_data.each do |pd|
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
  OrganisationProduct.find_or_create_by!(organisation: org, product: product)
end
puts "  Products      : #{products_data.size} products created/found"

# ══════════════════════════════════════════════════════════════════════════════
# SUPPLIER — Asian Paints Limited
# ══════════════════════════════════════════════════════════════════════════════
supplier = Supplier.find_or_create_by!(organisation: org, gstin: "19AAACA3622K1ZS") do |s|
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
puts "  Supplier      : #{supplier.name}"

# ══════════════════════════════════════════════════════════════════════════════
# CUSTOMERS
# ══════════════════════════════════════════════════════════════════════════════
customer = Customer.find_or_create_by!(organisation: org, name: "Kolkata Hardware & Civil Supplies") do |c|
  c.gstin      = "19AABCK1234A1ZP"
  c.pan        = "AABCK1234A"
  c.state      = "West Bengal"
  c.state_code = "19"
  c.phone      = "9830012345"
  c.active     = true
  c.metadata   = {
    "address"        => "45 B.B. Ganguly Street, Kolkata - 700012",
    "email"          => "procurement@kolkatahardware.com",
    "credit_limit"   => 50000,
    "credit_days"    => 15,
    "contact_person" => "Ramesh Agarwal"
  }
end
puts "  Customer (B2B): #{customer.name}"

walkin = Customer.find_or_create_by!(organisation: org, name: "Walk-in Customer") do |c|
  c.state      = "West Bengal"
  c.state_code = "19"
  c.active     = true
  c.metadata   = {}
end
puts "  Customer (B2C): #{walkin.name}"

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