module Suppliers
  module ShalimarPaints
    # Two-stage product matching for Shalimar Paints.
    #
    # Shalimar invoice description format: "12601744/Hero Weather Guard 12 Ex Eml Deep base"
    #   → material_code = "12601744"   (prefix before "/")
    #   → description   = "Hero Weather Guard 12 Ex Eml Deep base"
    #
    # Stage A: material_code + normalised pack_code  (exact)
    # Stage B: description keywords + normalised pack_code  (ILIKE, unique result only)
    # Stage C: UNMATCHED
    #
    # Pack normalisation: "900.0 ML" → "900ml", "3.6 LT" → "3.6l", "18.0" → "18l"
    #
    class Matcher < Suppliers::Base::Matcher
      # Noise words stripped from description before keyword ILIKE search
      NOISE_WORDS = %w[ex eml ext base coat primer the and for of in on at to].freeze

      def self.call(items, organisation)
        product_map = {}
        items.each do |item|
          key = item_key(item)
          next if key.blank?
          product = find_by_stages(
            item['material_code'].to_s.strip,
            item['description'].to_s,
            normalise_pack(item['pack_size'].to_s),
            organisation
          )
          product_map[key] = product if product
        end
        {
          product_map:  product_map,
          match_key_fn: ->(item) { Suppliers::ShalimarPaints::Matcher.item_key(item) }
        }
      end

      def self.find_product(metadata, organisation)
        return nil unless organisation
        find_by_stages(
          metadata['material_code'].to_s.strip,
          metadata['description'].to_s,
          normalise_pack(metadata['pack_size'].to_s),
          organisation
        )
      end

      def self.display_code(item)
        item['material_code'].to_s.presence
      end

      def self.item_key(item)
        code = item['material_code'].to_s.strip
        pack = normalise_pack(item['pack_size'].to_s)
        return nil if code.blank? && item['description'].blank?
        "#{code}|#{pack}"
      end

      # ── Normalise pack size strings ────────────────────────────────────────
      # "900.0 ML" → "900ml"   "3.6 LT" → "3.6l"   "18.0" → "18l"
      def self.normalise_pack(raw)
        return '' if raw.blank?
        s = raw.to_s.strip.downcase.gsub(/\s+/, '')
        s = s.gsub(/(\d+)\.0([a-z])/, '\1\2')   # "900.0ml" → "900ml"
        s = s.gsub(/(\d+)\.0$/, '\1')            # "18.0"    → "18"
        s = s.gsub(/litres?|ltr/, 'l')
        s = s.gsub(/(?<!\d)lt$/, 'l')            # trailing "lt" → "l"
        s = s.gsub(/ml$/, 'ml')                  # keep ml as-is
        # bare number with no unit → assume litres (Shalimar convention)
        s = "#{s}l" if s.match?(/\A[\d.]+\z/)
        s
      end

      private_class_method def self.find_by_stages(material_code, description, norm_pack, organisation)
        return nil if norm_pack.blank?

        # Stage A — material_code + pack_code
        if material_code.present?
          result = Product.for_org(organisation)
                          .where('LOWER(TRIM(material_code)) = ?', material_code.downcase.strip)
                          .where(pack_sql, "%#{norm_pack}%")
                          .first
          return result if result
        end

        # Stage B — description keywords + pack_code
        keywords = extract_keywords(description)
        return nil if keywords.blank?

        results = Product.for_org(organisation)
                         .where('LOWER(description) LIKE ?', "%#{keywords.downcase}%")
                         .where(pack_sql, "%#{norm_pack}%")
        results.count == 1 ? results.first : nil
      end

      private_class_method def self.pack_sql
        "LOWER(REPLACE(REPLACE(REPLACE(REPLACE(pack_code,' ',''),'.0',''),'ltr','l'),'litres','l')) LIKE ?"
      end

      private_class_method def self.extract_keywords(description)
        # Strip material_code prefix if present ("12601744/Hero..." → "Hero...")
        clean = description.to_s.split('/').last.to_s.strip
        words = clean.split(/\s+/).reject do |w|
          w.length < 3 ||
            NOISE_WORDS.include?(w.downcase) ||
            w.match?(/\A[\d.]+\z/)
        end
        words.first(4).join(' ')
      end
    end
  end
end
