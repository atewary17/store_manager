class AddAliasesToUomsAndBrands < ActiveRecord::Migration[7.1]
  def up
    add_column :uoms,   :aliases, :string, array: true, default: []
    add_column :brands, :aliases, :string, array: true, default: []

    # GIN index enables fast ANY(aliases) lookups
    add_index :uoms,   :aliases, using: :gin, name: 'idx_uoms_aliases_gin'
    add_index :brands, :aliases, using: :gin, name: 'idx_brands_aliases_gin'

    # ── Seed common UOM aliases ───────────────────────────────────────────────
    # Stored lowercase so matching is case-insensitive (normalise before lookup)
    uom_aliases = {
      'Pieces'   => %w[pcs pc nos no. unit units each ea no piece],
      'Kilogram' => %w[kg kgs kilo kilos kilogram],
      'Gram'     => %w[g gm gms grm gram grams],
      'Litre'    => %w[l ltr ltrs liter liters litre litres],
      'Millilitre' => %w[ml mls milliliter millilitre],
      'Carton'   => %w[ctn ctns crtn box boxes bx cartoon cartons],
      'Bag'      => %w[bags bgs bag sack sacks],
      'Bundle'   => %w[bnd bundle bundles bdle],
      'Dozen'    => %w[dz dzn doz dozen dozens],
      'Metre'    => %w[m mtr mtrs meter meters metre metres],
      'Feet'     => %w[ft fts foot feet],
      'Square Feet' => %w[sqft sq.ft sq ft sft],
      'Tin'      => %w[tin tins],
      'Drum'     => %w[drm drum drums],
      'Pair'     => %w[pr pair pairs],
      'Roll'     => %w[rl roll rolls rll],
      'Set'      => %w[set sets],
      'Packet'   => %w[pkt pkts packet packets pack packs],
      'Bottle'   => %w[btl bottle bottles],
      'Can'      => %w[can cans canister],
      'Tube'     => %w[tube tubes],
    }

    uom_aliases.each do |name, aliases|
      uom = Uom.find_by('LOWER(name) = ?', name.downcase) ||
            Uom.find_by('LOWER(short_name) = ?', name.downcase[0..9])
      uom&.update_columns(aliases: aliases)
    end

    # ── Seed common brand aliases ─────────────────────────────────────────────
    brand_aliases = {
      'Asian Paints'   => %w[asian ap asian-paints asianpaint],
      'Berger Paints'  => %w[berger bp berger-paints bergerpaint],
      'Nerolac'        => %w[nerolac kansai kansai-nerolac],
      'Dulux'          => %w[dulux ici akzonobel],
      'Nippon Paint'   => %w[nippon nipponpaint],
      'Jotun'          => %w[jotun],
      'Pidilite'       => %w[pidilite fevicol fevicryl],
    }

    brand_aliases.each do |name, aliases|
      brand = Brand.find_by('LOWER(name) = ?', name.downcase)
      brand&.update_columns(aliases: aliases)
    end
  end

  def down
    remove_index :uoms,   name: 'idx_uoms_aliases_gin'
    remove_index :brands, name: 'idx_brands_aliases_gin'
    remove_column :uoms,   :aliases
    remove_column :brands, :aliases
  end
end
