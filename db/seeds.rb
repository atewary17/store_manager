# db/seeds.rb
# Run with: rails db:seed
# Safe to re-run — all records use find_or_create_by! so nothing is duplicated.

puts "\n Seeding MyStoreManager database...\n"

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
puts "  User          : #{user.full_name} <#{user.email}> — #{user.role}"

# ══════════════════════════════════════════════════════════════════════════════
# UNITS OF MEASURE
# Each entry: [name, short_name, aliases]
# ══════════════════════════════════════════════════════════════════════════════
uom_data = [
  # ── Fallback ──────────────────────────────────────────────────────────────
  { name: "Others",       short_name: "OTH",  aliases: %w[other oth misc miscellaneous na n/a unknown] },

  # ── Count / discrete ──────────────────────────────────────────────────────
  { name: "Units",        short_name: "UNT",  aliases: %w[unit units unt nos no. nos. number numbers] },
  { name: "Pieces",       short_name: "Pcs",  aliases: %w[pcs pc piece piec each ea] },
  { name: "Numbers",      short_name: "Nos",  aliases: %w[no. num] },
  { name: "Pair",         short_name: "Pr",   aliases: %w[pair pairs pr] },
  { name: "Set",          short_name: "Set",  aliases: %w[set sets] },
  { name: "Box",          short_name: "Box",  aliases: %w[box boxes bx] },
  { name: "Carton",       short_name: "Ctn",  aliases: %w[ctn carton cartons ct] },
  { name: "Pack",         short_name: "Pkt",  aliases: %w[pkt pack packs packet packets pk pck] },
  { name: "Bundle",       short_name: "Bdl",  aliases: %w[bdl bundle bundles bndl] },
  { name: "Roll",         short_name: "Roll", aliases: %w[roll rolls rll rl] },
  { name: "Sheet",        short_name: "Sht",  aliases: %w[sht sheet sheets sh] },
  { name: "Bag",          short_name: "Bag",  aliases: %w[bag bags bg] },
  { name: "Drum",         short_name: "Drm",  aliases: %w[drm drum drums dr] },
  { name: "Can",          short_name: "Can",  aliases: %w[can cans] },
  { name: "Tin",          short_name: "Tin",  aliases: %w[tin tins tn] },
  { name: "Bottle",       short_name: "Btl",  aliases: %w[btl bottle bottles bot] },
  { name: "Tube",         short_name: "Tube", aliases: %w[tube tubes tub] },
  { name: "Coil",         short_name: "Coil", aliases: %w[coil coils] },
  { name: "Strip",        short_name: "Str",  aliases: %w[str strip strips] },
  { name: "Gross",        short_name: "Grs",  aliases: %w[grs gross] },
  { name: "Dozen",        short_name: "Doz",  aliases: %w[doz dozen dozens dz] },
  { name: "Ream",         short_name: "Ream", aliases: %w[ream reams rm] },

  # ── Weight ────────────────────────────────────────────────────────────────
  { name: "Kilogram",     short_name: "Kg",   aliases: %w[kg kgs kilogram kilograms kilo kilos] },
  { name: "Gram",         short_name: "Gm",   aliases: %w[gm gms gram grams g gr] },
  { name: "Milligram",    short_name: "Mg",   aliases: %w[mg milligram milligrams] },
  { name: "Quintal",      short_name: "Qtl",  aliases: %w[qtl quintal quintals q.] },
  { name: "Metric Ton",   short_name: "MT",   aliases: %w[mt m.t. metric ton metric tons tonne tonnes ton tons t] },

  # ── Volume / liquid ───────────────────────────────────────────────────────
  { name: "Litre",        short_name: "Ltr",  aliases: %w[ltr ltrs litre litres liter liters l lt] },
  { name: "Millilitre",   short_name: "ML",   aliases: %w[ml mls millilitre millilitres milliliter milliliters] },
  { name: "Kilolitre",    short_name: "KL",   aliases: %w[kl kilolitre kilolitres kiloliter kiloliters] },

  # ── Length / area ─────────────────────────────────────────────────────────
  { name: "Metre",        short_name: "Mtr",  aliases: %w[mtr mtrs metre metres meter meters m.] },
  { name: "Centimetre",   short_name: "Cm",   aliases: %w[cm cms centimetre centimetres centimeter centimeters] },
  { name: "Millimetre",   short_name: "Mm",   aliases: %w[mm mms millimetre millimetres millimeter millimeters] },
  { name: "Foot",         short_name: "Ft",   aliases: %w[ft feet foot'] },
  { name: "Inch",         short_name: "In",   aliases: %w[in inch inches"] },
  { name: "Square Metre", short_name: "Sqm",  aliases: %w[sqm sq.m sq m2 square metre square meter sqmt] },
  { name: "Square Foot",  short_name: "Sqft", aliases: %w[sqft sq.ft sq ft ft2 square foot square feet] },
  { name: "Running Metre",short_name: "Rmt",  aliases: %w[rmt rm r.mt running metre running meter r/m] },
]

uom_data.each do |d|
  uom = Uom.find_or_create_by!(name: d[:name]) do |u|
    u.short_name = d[:short_name]
    u.active     = true
    u.aliases    = d[:aliases]
  end
  # Update aliases on existing records too
  uom.update_columns(aliases: d[:aliases]) if uom.aliases != d[:aliases]
end

puts "  UOMs          : #{Uom.count} total"

# ══════════════════════════════════════════════════════════════════════════════
# PRODUCT CATEGORIES
# ══════════════════════════════════════════════════════════════════════════════
category_data = [
  # ── Fallback ──────────────────────────────────────────────────────────────
  { name: "Others",               description: "Uncategorised or unclassified products",                                      is_paint_type: false },

  # ── Paints & Coatings ─────────────────────────────────────────────────────
  { name: "Paints",               description: "All types of paint products — enamel, emulsion, primer, distemper",           is_paint_type: true  },
  { name: "Exterior Paints",      description: "Weather-resistant exterior wall paints and coatings",                         is_paint_type: true  },
  { name: "Interior Paints",      description: "Interior wall paints — emulsion, distemper, texture",                        is_paint_type: true  },
  { name: "Enamel Paints",        description: "Glossy enamel paints for metal, wood, and surfaces",                         is_paint_type: true  },
  { name: "Primers",              description: "Primers and undercoats for walls, wood, and metal",                           is_paint_type: true  },
  { name: "Wood Finishes",        description: "Varnishes, wood stains, lacquers, and sealers",                               is_paint_type: true  },
  { name: "Metal Coatings",       description: "Anti-rust, galvanising, and metal protective coatings",                      is_paint_type: true  },
  { name: "Waterproofing",        description: "Waterproofing compounds, sealants, and solutions",                           is_paint_type: false },
  { name: "Texture Finishes",     description: "Textured wall finishes and decorative coatings",                              is_paint_type: true  },
  { name: "Putty & Filler",       description: "Wall putty, crack filler, and surface preparation compounds",                is_paint_type: false },
  { name: "Distemper",            description: "Dry and oil-bound distemper products",                                        is_paint_type: true  },
  { name: "Thinners & Solvents",  description: "Paint thinners, turpentine, and cleaning solvents",                          is_paint_type: false },
  { name: "Painting Accessories", description: "Brushes, rollers, masking tape, mixing tools, and other painting aids",      is_paint_type: false },

  # ── Hardware & Fasteners ──────────────────────────────────────────────────
  { name: "Hardware",             description: "General hardware items — fasteners, fittings, fixtures",                     is_paint_type: false },
  { name: "Fasteners",            description: "Screws, nails, bolts, nuts, washers, and rivets",                            is_paint_type: false },
  { name: "Locks & Hinges",       description: "Door locks, padlocks, hinges, door closers, and security fittings",         is_paint_type: false },
  { name: "Handles & Knobs",      description: "Door handles, cabinet knobs, drawer pulls",                                  is_paint_type: false },

  # ── Plumbing & Sanitary ───────────────────────────────────────────────────
  { name: "Plumbing",             description: "Pipes, fittings, taps, valves, and plumbing accessories",                    is_paint_type: false },
  { name: "Sanitary Ware",        description: "Bathroom fittings — basins, commodes, showers, and accessories",            is_paint_type: false },

  # ── Electrical ────────────────────────────────────────────────────────────
  { name: "Electrical",           description: "Wires, switches, sockets, MCBs, and electrical accessories",                 is_paint_type: false },

  # ── Adhesives & Sealants ──────────────────────────────────────────────────
  { name: "Adhesives & Sealants", description: "Adhesives, construction chemicals, silicone sealants, and bonding agents",  is_paint_type: false },

  # ── Flooring & Tiles ──────────────────────────────────────────────────────
  { name: "Flooring",             description: "Floor tiles, laminates, vinyl, and flooring accessories",                    is_paint_type: false },
  { name: "Tiles",                description: "Wall and floor tiles — ceramic, vitrified, mosaic",                          is_paint_type: false },

  # ── Tools ─────────────────────────────────────────────────────────────────
  { name: "Hand Tools",           description: "Hammers, screwdrivers, wrenches, pliers, and manual tools",                  is_paint_type: false },
  { name: "Power Tools",          description: "Drills, grinders, sanders, and power tool accessories",                     is_paint_type: false },
  { name: "Safety Equipment",     description: "Helmets, gloves, goggles, safety harnesses, and PPE",                       is_paint_type: false },

  # ── Construction Materials ────────────────────────────────────────────────
  { name: "Cement & Concrete",    description: "Cement, concrete mix, ready-mix, and construction compounds",               is_paint_type: false },
  { name: "Steel & Iron",         description: "TMT bars, steel sections, pipes, and ferrous materials",                    is_paint_type: false },
  { name: "Timber & Boards",      description: "Plywood, MDF, hardboard, timber, and wood panels",                         is_paint_type: false },
  { name: "Glass & Mirrors",      description: "Float glass, toughened glass, mirrors, and glazing accessories",            is_paint_type: false },

  # ── Stationery & Packaging ────────────────────────────────────────────────
  { name: "Stationery",           description: "Stationery, office supplies, and printed material",                          is_paint_type: false },
  { name: "Packaging Material",   description: "Cartons, wrapping, bubble wrap, and packing supplies",                      is_paint_type: false },
]

category_data.each do |d|
  cat = ProductCategory.find_or_create_by!(name: d[:name]) do |c|
    c.description  = d[:description]
    c.is_paint_type = d[:is_paint_type]
    c.active       = true
  end
  # Enrol in org
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
  # ── Fallback ──────────────────────────────────────────────────────────────
  { name: "Others",             short_name: "OTH",  aliases: %w[other others misc unknown unbranded generic] },

  # ── Paints ────────────────────────────────────────────────────────────────
  { name: "Asian Paints",       short_name: "AP",   aliases: %w[asian ap asian-paints asianpaints a.p. ap-ltd] },
  { name: "Berger Paints",      short_name: "BRG",  aliases: %w[berger brg bergerpaint bergerpaints berger-paints] },
  { name: "Nerolac",            short_name: "NRL",  aliases: %w[nerolac nrl kansai kansai-nerolac goodlass] },
  { name: "Dulux",              short_name: "DLX",  aliases: %w[dulux dlx akzo akzo-nobel ici paints] },
  { name: "Indigo Paints",      short_name: "IND",  aliases: %w[indigo ind indigo-paints indigopaints] },
  { name: "Shalimar Paints",    short_name: "SHL",  aliases: %w[shalimar shl shalimar-paints] },
  { name: "Nippon Paint",       short_name: "NIP",  aliases: %w[nippon nip nippon-paint nipponpaint] },
  { name: "JSW Paints",         short_name: "JSW",  aliases: %w[jsw jsw-paints jswpaints] },

  # ── Hardware & Tools ──────────────────────────────────────────────────────
  { name: "Stanley",            short_name: "STN",  aliases: %w[stanley stn stanley-tools] },
  { name: "Taparia",            short_name: "TAP",  aliases: %w[taparia tap] },
  { name: "Bosch",              short_name: "BSH",  aliases: %w[bosch bsh] },
  { name: "Makita",             short_name: "MKT",  aliases: %w[makita mkt] },
  { name: "Black & Decker",     short_name: "B&D",  aliases: %w[black&decker b&d black-decker blackdecker] },
  { name: "Dewalt",             short_name: "DWT",  aliases: %w[dewalt dwt de-walt] },

  # ── Fasteners & Fittings ──────────────────────────────────────────────────
  { name: "Hettich",            short_name: "HTT",  aliases: %w[hettich htt] },
  { name: "Dorset",             short_name: "DRS",  aliases: %w[dorset drs] },
  { name: "Hafele",             short_name: "HFL",  aliases: %w[hafele hfl häfele] },
  { name: "Godrej",             short_name: "GDJ",  aliases: %w[godrej gdj] },
  { name: "Yale",               short_name: "YLE",  aliases: %w[yale yle] },

  # ── Plumbing ──────────────────────────────────────────────────────────────
  { name: "Astral Pipes",       short_name: "AST",  aliases: %w[astral ast astral-pipes astralpipes] },
  { name: "Finolex",            short_name: "FNX",  aliases: %w[finolex fnx] },
  { name: "Supreme Industries", short_name: "SUP",  aliases: %w[supreme sup supreme-ind] },
  { name: "Prince Pipes",       short_name: "PRP",  aliases: %w[prince prp prince-pipes] },
  { name: "Jaguar",             short_name: "JAG",  aliases: %w[jaguar jag] },
  { name: "Jaquar",             short_name: "JQR",  aliases: %w[jaquar jqr] },
  { name: "Cera",               short_name: "CRA",  aliases: %w[cera cra] },
  { name: "Hindware",           short_name: "HNW",  aliases: %w[hindware hnw hind-ware] },

  # ── Electrical ────────────────────────────────────────────────────────────
  { name: "Havells",            short_name: "HVL",  aliases: %w[havells hvl] },
  { name: "Polycab",            short_name: "PLY",  aliases: %w[polycab ply] },
  { name: "Finolex Cables",     short_name: "FNC",  aliases: %w[finolex-cables fnc finolex cables] },
  { name: "Legrand",            short_name: "LGR",  aliases: %w[legrand lgr] },
  { name: "Schneider",          short_name: "SCH",  aliases: %w[schneider sch schneider-electric] },
  { name: "Anchor",             short_name: "ANC",  aliases: %w[anchor anc anchor-electricals] },

  # ── Adhesives & Construction Chemicals ────────────────────────────────────
  { name: "Pidilite",           short_name: "PDL",  aliases: %w[pidilite pdl fevicol fevicryl dr.fixit dr fixit] },
  { name: "Fevicol",            short_name: "FVC",  aliases: %w[fevicol fvc pidilite-fevicol] },
  { name: "Dr. Fixit",          short_name: "DRF",  aliases: %w[dr.fixit drfixit dr-fixit drf] },
  { name: "Ultratech",          short_name: "UTC",  aliases: %w[ultratech utc ultratech-cement] },
  { name: "ACC",                short_name: "ACC",  aliases: %w[acc a.c.c acc-cement] },
  { name: "Ambuja Cement",      short_name: "AMB",  aliases: %w[ambuja amb ambuja-cement] },
]

brand_data.each do |d|
  brand = Brand.find_or_create_by!(name: d[:name]) do |b|
    b.short_name  = d[:short_name]
    b.active      = true
    b.aliases     = d[:aliases]
  end
  brand.update_columns(aliases: d[:aliases]) if brand.aliases != d[:aliases]
end

puts "  Brands        : #{Brand.count} total"

# ══════════════════════════════════════════════════════════════════════════════
# PRODUCTS (10 products from actual DB — Asian Paints enamel range)
# ══════════════════════════════════════════════════════════════════════════════
cat_paints  = ProductCategory.find_by!(name: "Paints")
brand_ap    = Brand.find_by!(name: "Asian Paints")
uom_pcs     = Uom.find_by!(name: "Pieces")

products_data = [
  { material_code: "00010210210", pack_code: "210", description: "AP APCO GLS ENML CAS GRN 1 LT",   mrp: 290.00 },
  { material_code: "00010506210", pack_code: "210", description: "AP APCO GLS ENML DPORANGE 1 LT",  mrp: 290.00 },
  { material_code: "00010616210", pack_code: "210", description: "AP APCO GLS ENML SM GREY 1 LT",   mrp: 262.00 },
  { material_code: "00014284210", pack_code: "210", description: "AP APCO GLS ENML DP MHGNY 1 LTR", mrp: 290.00 },
  { material_code: "0001M003050", pack_code: "050", description: "AP APCO GLS ENML GOLD 50 ML",      mrp: 125.00 },
  { material_code: "0001M003120", pack_code: "120", description: "AP APCO GLS ENML GOLD 200 ML",     mrp: 390.00 },
  { material_code: "00070908150", pack_code: "150", description: "AP WOOD PRIMER WHITE 500ML",        mrp: 215.00 },
  { material_code: "00010125120", pack_code: "120", description: "AP APCO GLS ENML SKY BLUE 200ML",  mrp: nil    },
  { material_code: "00010119050", pack_code: "050", description: "AP APCO GLS ENML OX BLUE 50 ML",  mrp: nil    },
  { material_code: "00010119110", pack_code: "110", description: "AP APCO GLS ENML OX BLUE 100ML",  mrp: nil    },
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
