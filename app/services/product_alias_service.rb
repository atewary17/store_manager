class ProductAliasService

  # Look up a product by raw invoice text for a given organisation.
  # Returns a Product or nil.
  def self.lookup(organisation, raw_text, supplier_id: nil)
    normalised = ProductAlias.normalise(raw_text)
    return nil if normalised.blank?

    aliases = ProductAlias
      .for_org(organisation.id)
      .where(normalised_text: normalised)
      .includes(:product)

    return nil if aliases.empty?

    chosen = if supplier_id.present?
      aliases.find { |a| a.supplier_id == supplier_id } ||
        aliases.find { |a| a.supplier_id.nil? }
    else
      aliases.find { |a| a.supplier_id.nil? } || aliases.first
    end

    return nil unless chosen

    chosen.update_column(:hit_count, chosen.hit_count + 1)
    chosen.product
  rescue => e
    Rails.logger.warn "[ProductAliasService#lookup] DB error: #{e.message}"
    nil
  end

  # Record (or update) an alias mapping raw invoice text → product for an org.
  # Returns the ProductAlias record or nil on error.
  def self.record(organisation, raw_text, product,
                  source:, confidence: 1.0, supplier_id: nil)
    normalised = ProductAlias.normalise(raw_text)
    return nil if normalised.blank?

    pa = ProductAlias.find_or_initialize_by(
      organisation_id: organisation.id,
      normalised_text: normalised
    )

    if pa.new_record?
      pa.raw_text     = raw_text
      pa.product      = product
      pa.source       = source
      pa.confidence   = confidence
      pa.supplier_id  = supplier_id
      pa.hit_count    = 1
    else
      if confidence > pa.confidence
        pa.source     = source
        pa.confidence = confidence
      end
      pa.hit_count += 1
    end

    pa.save!
    pa
  rescue => e
    Rails.logger.warn "[ProductAliasService#record] DB error: #{e.message}"
    nil
  end

end
