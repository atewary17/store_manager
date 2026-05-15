# app/jobs/product_import_job.rb
require 'roo'
require 'base64'

class ProductImportJob < ApplicationJob
  queue_as :default

  # Organisation id=1 is the master/superadmin org.
  # Only imports from this org are allowed to update master product fields.
  MASTER_ORG_ID = 1

  # Columns whose leading zeros must survive (read via formatted_value).
  CODE_COLS = %w[material_code product_code pack_code hsn_code shade_code].freeze

  def perform(product_import_id)
    import = ProductImport.find(product_import_id)
    import.update!(status: 'processing')

    file_data = Base64.decode64(import.file_data)
    tmp = Tempfile.new(['import', '.xlsx'])
    tmp.binmode
    tmp.write(file_data)
    tmp.flush

    # Use Roo::Excelx directly so we can call formatted_value for code columns
    xlsx  = Roo::Excelx.new(tmp.path)
    xlsx.default_sheet = xlsx.sheets.first
    sheet = xlsx.sheet(0)

    headers = sheet.row(1).map do |h|
      h = h.to_s.strip.downcase
      if h.start_with?('meta:')
        'meta:' + h.sub('meta:', '').gsub(/\s+/, '_')
      else
        h.gsub(/\s+/, '_')
      end
    end
    # Map header name → 1-indexed column for formatted_value reads
    col_index = headers.each_with_index.to_h { |h, i| [h, i + 1] }

    # Skip meta/descriptor rows from template
    data_start = 2
    (2..4).each do |r|
      first_cell = sheet.row(r).first.to_s.strip.downcase
      if %w[required optional required*].any? { |s| first_cell.start_with?(s) } ||
         first_cell.include?('must match') || first_cell.include?('text —')
        data_start = r + 1
      else
        break
      end
    end

    total_rows = sheet.last_row - (data_start - 1)
    import.update!(total_rows: total_rows)

    success_count = 0
    update_count  = 0
    error_count   = 0
    error_rows    = []

    (data_start..sheet.last_row).each do |row_num|
      row_data = headers.zip(sheet.row(row_num)).to_h.with_indifferent_access
      # Override code columns with formatted_value to preserve leading zeros
      CODE_COLS.each do |key|
        next unless col_index.key?(key)
        row_data[key] = xlsx.formatted_value(row_num, col_index[key]).to_s.strip
      end
      next if row_data.values.all? { |v| v.to_s.strip.blank? }

      begin
        result = process_row(row_data, import.organisation)
        # :created  → new product added to master catalogue
        # :updated  → existing product master fields updated (master org only)
        # :enrolled → existing product, just enrolled/updated in this org
        if result == :created
          success_count += 1
        elsif result == :updated || result == :enrolled
          update_count  += 1
          success_count += 1
        end
      rescue => e
        error_count += 1
        error_rows << row_data.merge('row_number' => row_num, 'error' => e.message)
      end
    end

    import.update!(
      status:        'done',
      success_count: success_count,
      update_count:  update_count,
      error_count:   error_count,
      error_rows:    error_rows,
      completed_at:  Time.current
    )

  rescue => e
    import.update!(
      status:       'failed',
      error_rows:   [{ 'error' => e.message }],
      completed_at: Time.current
    )
  ensure
    tmp&.close
    tmp&.unlink
  end

  private

  def process_row(row, organisation)
    # ── Resolve category ──
    category_name = row['category'].to_s.strip
    raise "Missing category" if category_name.blank?
    category = ProductCategory.where('LOWER(name) = LOWER(?)', category_name).first
    raise "Category '#{category_name}' not found" unless category

    # ── Resolve UOM ──
    uom_val = row['uom'].to_s.strip
    raise "Missing UOM" if uom_val.blank?
    uom = Uom.where('LOWER(short_name) = LOWER(?)', uom_val).first ||
          Uom.where('LOWER(name) = LOWER(?)', uom_val).first
    raise "UOM '#{uom_val}' not found" unless uom

    # ── Import key ──
    import_key   = ProductCategory.column_names.include?('import_key') ?
                     (category.import_key.presence || 'material_code') : 'material_code'
    import_value = row[import_key].to_s.strip

    # ── Find existing master product ──
    existing = import_value.present? ?
      Product.where("LOWER(TRIM(#{import_key})) = LOWER(?)", import_value.downcase).first : nil

    # ── Org-level overrides (always go into organisation_products) ──
    org_overrides = build_org_overrides(row)

    is_master_org = organisation.id == MASTER_ORG_ID

    result = if existing
      # Product already exists in master catalogue
      if is_master_org
        # Master org: allowed to update product master fields
        attrs = build_product_attrs(row, category, uom)
        # Merge metadata — don't wipe keys that aren't in the import file
        attrs[:metadata] = (existing.metadata || {}).merge(attrs[:metadata] || {})
        existing.assign_attributes(attrs)
        raise existing.errors.full_messages.join(', ') unless existing.valid?
        existing.save!
        :updated
      else
        # Regular org: never touch master product — match only
        :enrolled
      end

      # Always upsert organisation_products for the importing org
      upsert_org_product(existing, organisation, org_overrides)

      result
    else
      # Product doesn't exist — create it regardless of org
      attrs   = build_product_attrs(row, category, uom)
      product = Product.new(attrs)
      raise product.errors.full_messages.join(', ') unless product.valid?
      product.save!
      Rails.logger.info "[ProductImportJob] Created product ##{product.id}: #{product.description}"                         "#{attrs[:metadata].any? ? ' (with metadata)' : ''}"

      upsert_org_product(product, organisation, org_overrides)
      :created
    end
  end

  # Upsert the organisation_products join record with org-level overrides.
  # mrp, internal_code, local_description live here — NOT on products.
  def upsert_org_product(product, organisation, overrides)
    op = OrganisationProduct.find_or_initialize_by(
      organisation_id: organisation.id,
      product_id:      product.id
    )
    op.active           = true
    op.mrp              = overrides[:mrp]              if overrides.key?(:mrp)
    op.internal_code    = overrides[:internal_code]    if overrides.key?(:internal_code)
    op.local_description = overrides[:local_description] if overrides.key?(:local_description)
    op.save!
  end

  # Fields that belong to the master products table
  def build_product_attrs(row, category, uom)
    gst_raw    = row['gst_rate'].to_s.strip.gsub('%', '')
    gst        = gst_raw.present? ? gst_raw.to_f : 18.0
    active_val = row['active'].to_s.strip.downcase
    active     = !%w[false 0 no inactive].include?(active_val)

    {
      product_category: category,
      base_uom:         uom,
      brand:            Brand.where('LOWER(name) = LOWER(?)', row['brand'].to_s.strip).first,
      pack_code:        row['pack_code'].to_s.strip.presence,
      shade_code:       row['shade_code'].to_s.strip.presence,
      description:      row['description'].to_s.strip,
      material_code:    row['material_code'].to_s.strip.presence,
      product_code:     row['product_code'].to_s.strip.presence,
      hsn_code:         row['hsn_code'].to_s.strip.presence,
      gst_rate:         gst,
      active:           active,
      metadata:         build_metadata_from_row(row)
    }
  end

  # Reads ALL meta:* columns from the import row and returns a metadata hash.
  # Works for both the well-known keys AND any custom meta: columns the user adds.
  # On update, existing metadata is merged — import only overwrites keys present in the file.
  def build_metadata_from_row(row)
    meta = {}

    # Scan every column in the row for the meta: prefix — handles custom columns too
    row.each do |col, raw_val|
      next unless col.to_s.start_with?('meta:')
      key = col.to_s.sub('meta:', '').strip
      val = raw_val.to_s.strip

      next if key.blank?

      # Coerce known boolean fields
      if key == 'tint'
        meta[key] = val.downcase == 'true' ? 'true' : (val.downcase == 'false' ? 'false' : val.presence)
      elsif key == 'ai_confidence' && val.present?
        meta[key] = val.to_f.to_s
      elsif key == 'canister_volume_ml' && val.present?
        meta[key] = val.to_i.to_s
      else
        meta[key] = val.presence
      end

      meta.delete(key) if meta[key].nil?
    end

    # Also accept a raw JSON column "metadata" (power user override)
    if row['metadata'].to_s.strip.start_with?('{')
      begin
        parsed = JSON.parse(row['metadata'])
        meta   = parsed.merge(meta)   # explicit meta: columns win over raw JSON
      rescue JSON::ParserError
        # ignore malformed JSON
      end
    end

    meta
  end

  # Fields that belong to organisation_products — org-specific overrides
  def build_org_overrides(row)
    overrides = {}

    mrp_raw = row['mrp'].to_s.strip
    overrides[:mrp] = mrp_raw.present? ? mrp_raw.to_f : nil

    ic = row['internal_code'].to_s.strip
    overrides[:internal_code] = ic.presence

    ld = row['local_description'].to_s.strip
    overrides[:local_description] = ld.presence

    overrides
  end
end