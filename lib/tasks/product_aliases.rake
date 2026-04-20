namespace :product_aliases do
  desc 'Seed alias table from existing active products. Run once after deployment.'
  task seed: :environment do

    total_products = 0
    total_aliases  = 0
    errors         = 0

    Product.active.find_each do |product|
      orgs = Organisation.joins(:organisation_products)
                         .where(organisation_products: { product_id: product.id })

      orgs.each do |org|
        [product.description, product.material_code].compact.each do |text|
          next if text.blank?
          result = ProductAliasService.record(
            org, text, product,
            source: 'exact', confidence: 1.0
          )
          result ? total_aliases += 1 : errors += 1
        end
      end

      total_products += 1
      print '.' if total_products % 50 == 0
    end

    puts ""
    puts "Done. #{total_aliases} aliases seeded across #{total_products} products. #{errors} errors."
  end
end

# Run with: rails product_aliases:seed
# Run once after Step 7 deployment to pre-warm Gate 3.
# Safe to run multiple times — upsert handles duplicates.
