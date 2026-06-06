module Suppliers
  module ShalimarPaints
    # Two-tier product matching for Shalimar Paints.
    #
    # Shalimar invoice description format: "12601744/Hero Weather Guard 12 Ex Eml Deep base"
    #   → material_code = "12601744"   (prefix before "/")
    #   → description   = "Hero Weather Guard 12 Ex Eml Deep base"
    #   → pack_size     = separate column, e.g. "3.6 LT", "900.0 ML"
    #
    # Tier 1 (Stage A): exact material_code match → disambiguate by normalised pack_size
    #   material_code identifies the product variant (not the SKU), so multiple pack
    #   sizes share the same code — pack_size is the tiebreaker.
    #
    # Tier 2 (Stage B): per-keyword AND matching + abbreviation expansion + pack_size
    #   "Hero Weather Guard 12 Ex Eml Deep base" expands to keyword set
    #   ["hero", "weather", "guard", "exterior", "emulsion", "deep"] and each
    #   keyword is required to appear in the product description (AND logic, not
    #   substring of the concatenated string). Pack size further filters candidates.
    #   Scored by keyword coverage; only returned if coverage is high enough.
    #
    # Pack normalisation: "900.0 ML" → "900ml", "3.6 LT" → "3.6lt", "18.0" → "18l"
    #
    class Matcher < Suppliers::Base::Matcher

      # Words that carry no discriminating signal for Shalimar products.
      # NOTE: "base" is intentionally NOT here — "Deep Base", "Yellow Base",
      # "Accent Base" are meaningful variant identifiers and must be kept.
      # NOTE: "hero", "weather", "guard" are intentionally NOT here — they
      # discriminate this product line against other Shalimar lines.
      NOISE_WORDS = %w[the and for of in on at to by].freeze

      # Shalimar uses abbreviated product names on invoices.
      # Expand before keyword extraction so they match the full-word system descriptions.
      ABBREVIATIONS = {
        /\bex\b/i    => 'exterior',
        /\beml\b/i   => 'emulsion',
        /\bext\b/i   => 'exterior',
        /\bint\b/i   => 'interior',
        /\bwbp\b/i   => 'primer',
        /\bprem\b/i  => 'premium',
        /\bsynth\b/i => 'synthetic',
        /\bwal\b/i   => 'wall',
        /\bacco?\b/i => 'accent',
        /\bdeep\b/i  => 'deep',
        /\byel\b/i   => 'yellow',
        /\bwht\b/i   => 'white',
        /\bpastel\b/i => 'pastel',
      }.freeze

      def self.call(items, organisation)
        product_map = {}
        items.each do |item|
          key = item_key(item)
          next if key.blank?
          product = find_by_tiers(
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
        find_by_tiers(
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
        # Include description fragment to avoid collisions when code is blank
        desc_fragment = item['description'].to_s.split('/').last.to_s.strip.downcase.first(20)
        key_parts = [code.presence, pack.presence, desc_fragment.presence].compact
        key_parts.any? ? key_parts.join('|') : nil
      end

      # ── Pack size normalisation ─────────────────────────────────────────────
      # Converts free-text pack sizes to a comparable lowercase string.
      # "900.0 ML" → "900ml"   "3.6 LT" → "3.6lt"   "18.0" → "18l"
      # BUG FIX: "LT" (unit only, no number) → "" — a pack without a numeric
      # component cannot be used for matching and must be treated as missing.
      def self.normalise_pack(raw)
        return '' if raw.blank?
        s = raw.to_s.strip.downcase.gsub(/\s+/, '')
        s = s.gsub(/(\d+)\.0([a-z])/, '\1\2')  # "900.0ml" → "900ml"
        s = s.gsub(/(\d+)\.0$/, '\1')           # "18.0"    → "18"
        s = s.gsub(/litres?|ltr/, 'l')
        s = s.gsub(/(?<!\d)lt$/, 'l')           # trailing "lt" not preceded by digit
        s = s.gsub(/ml$/, 'ml')
        # bare number with no unit → assume litres (Shalimar convention)
        s = "#{s}l" if s.match?(/\A[\d.]+\z/)
        # No digits at all → unit-only string (e.g. "l" from "LT") → not a valid pack
        return '' unless s.match?(/\d/)
        s
      end

      private_class_method def self.find_by_tiers(material_code, description, norm_pack, organisation)
        # BUG FIX: Shalimar invoices always have a numeric pack_size column.
        # A blank norm_pack means the item is invalid/unparseable — skip matching.
        return nil if norm_pack.blank?

        # ── Tier 1: product_code + pack_size (exact) ───────────────────────
        result = tier1(material_code, norm_pack, description, organisation)
        return result if result

        # ── Tier 2: expanded keyword AND-match + pack_size + family check ───
        tier2(description, norm_pack, organisation)
      end

      # Tier 1 — product_code narrows to variant family; pack_size picks the SKU.
      #
      # Shalimar's invoice code (e.g. "12601744") is a product-family identifier
      # shared across all pack sizes of the same variant. It is stored in the
      # products table as product_code (non-unique), NOT material_code (unique).
      # Pack size is the tiebreaker to reach the specific SKU.
      # After finding the match, family_match? validates it against the invoice
      # description as a final safety check.
      private_class_method def self.tier1(material_code, norm_pack, description, organisation)
        return nil if material_code.blank?

        family = Product.for_org(organisation)
                        .where('LOWER(TRIM(product_code)) = ?', material_code.downcase.strip)

        return nil if family.none?

        match = family.where(pack_sql, "%#{norm_pack}%").first

        unless match
          # Pack normalisation might have edge-case mismatches — try numeric-only
          num   = norm_pack.gsub(/[a-z]/, '')
          match = family.where("LOWER(REPLACE(pack_code, ' ', '')) LIKE ?", "%#{num}%").first if num.present?
        end

        # Single-SKU fallback: only one product in the family and pack is unambiguous
        match ||= (family.count == 1 ? family.first : nil)

        # Family cross-check: if the matched product has a product_family set,
        # verify the invoice description contains those words before accepting.
        return nil if match && !family_match?(match, description)

        match
      end

      # Tier 2 — expand abbreviations, extract keywords, AND-match each against
      # the org's Shalimar product descriptions, then rank by coverage + pack match.
      # product_family cross-check is applied before scoring to eliminate false positives.
      private_class_method def self.tier2(description, norm_pack, organisation)
        keywords = extract_keywords(description)
        return nil if keywords.size < 2

        scope = Product.for_org(organisation)

        # Each keyword must be present in the description (AND logic)
        keywords.each do |kw|
          scope = scope.where('LOWER(description) LIKE ?', "%#{kw}%")
        end

        # Narrow to Shalimar brand so we don't bleed into other suppliers
        shalimar_brand = Brand.where('LOWER(name) LIKE ?', '%shalimar%').first
        scope = scope.where(brand: shalimar_brand) if shalimar_brand

        # Apply pack_size filter
        scope = scope.where(pack_sql, "%#{norm_pack}%") if norm_pack.present?

        candidates = scope.to_a
        return nil if candidates.empty?

        # Apply product_family cross-check: keep only candidates whose stored
        # product_family keywords are all present in the invoice description.
        # Products without a product_family set pass through (graceful fallback).
        validated = candidates.select { |p| family_match?(p, description) }
        return nil if validated.empty?
        return validated.first if validated.size == 1

        # Multiple candidates — score by keyword coverage, return best if above threshold
        scored      = validated.map do |product|
          desc_lower = product.description.to_s.downcase
          coverage   = keywords.count { |kw| desc_lower.include?(kw) }
          [product, coverage]
        end
        best_product, best_coverage = scored.max_by { |_, c| c }
        min_coverage = [(keywords.size * 0.6).ceil, 2].max
        best_coverage >= min_coverage ? best_product : nil
      end

      # Cross-checks the invoice description against the product's stored
      # metadata['product_family'] (e.g. "HERO WEATHER GUARD").
      # Returns true if:
      #   - the product has no product_family set (no constraint → pass through), OR
      #   - every word of the product_family appears in the invoice description.
      private_class_method def self.family_match?(product, invoice_description)
        family = product.metadata&.dig('product_family').to_s.strip
        return true if family.blank?

        inv_lower    = invoice_description.to_s.downcase
        family_words = family.downcase.split.select { |w| w.length >= 3 }
        family_words.all? { |w| inv_lower.include?(w) }
      end

      # Shared pack_code normalisation SQL — used in both tiers.
      private_class_method def self.pack_sql
        "LOWER(REPLACE(REPLACE(REPLACE(REPLACE(pack_code,' ',''),'.0',''),'ltr','l'),'litres','l')) LIKE ?"
      end

      # Extract meaningful search keywords from a Shalimar product description.
      # Steps:
      #   1. Strip material_code prefix (before '/')
      #   2. Expand abbreviations ("Ex" → "exterior", "Eml" → "emulsion")
      #   3. Remove noise words, short tokens, pure numbers
      #   4. Return lowercase array (NOT a joined string — callers do AND matching)
      private_class_method def self.extract_keywords(description)
        clean = description.to_s.split('/').last.to_s.strip
        return [] if clean.blank?

        expanded = expand_abbreviations(clean)

        words = expanded.downcase.split(/\s+/).reject do |w|
          w.length < 3 ||
            NOISE_WORDS.include?(w) ||
            w.match?(/\A[\d.]+\z/)
        end

        words.first(6).uniq
      end

      private_class_method def self.expand_abbreviations(text)
        result = text.dup
        ABBREVIATIONS.each { |pattern, replacement| result = result.gsub(pattern, replacement) }
        result
      end
    end
  end
end
