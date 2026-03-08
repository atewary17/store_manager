# # db/seeds.rb

# puts "🌱 Seeding database..."

# # ── Organisation ──────────────────────────────────────────
# org = Organisation.find_or_create_by!(name: "Oracle PVT LTD") do |o|
#   o.gst_number        = "27AABCU9603R1ZX"   
#   o.address           = "Mumbai, Maharashtra, India"
#   o.subscription_plan = "basic"
#   o.status            = :active
# end
# puts "✅ Organisation: #{org.name} (ID: #{org.id})"

# # ── User ──────────────────────────────────────────────────
# user = User.find_or_create_by!(email: "atewary17@gmail.com") do |u|
#   u.first_name = "Anish"
#   u.last_name  = "Tewary"
#   u.password   = "asansol8"
#   u.password_confirmation = "asansol8"
#   u.role         = :super_admin
#   u.status       = :active
#   u.organisation = org
# end
# puts "✅ User: #{user.full_name} <#{user.email}> — #{user.role} @ #{org.name}"

# puts "\n✅ Seeding complete!"
# puts "   Email:    atewary17@gmail.com"
# puts "   Password: asansol8"