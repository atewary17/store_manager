# app/jobs/product_import_job.rb
require 'roo'
require 'base64'

class ProductImportJob < ApplicationJob
  queue_as :default

  def perform(product_import_id)
    import = ProductImport.find(product_import_id)
    import.update!(status: 'processing')

    # Decode and write to tempfile
    file_data = Base64.decode64(import.file_data)
    tmp = Tempfile.new(['import', '.xlsx'])
    tmp.binmode
    tmp.write(file_data)
    tmp.flush

    xlsx  = Roo::Spreadsheet.open(tmp.path, extension: :xlsx)
    sheet = xlsx.sheet(0)

    # Normalise headers
    headers = sheet.row(1).map { |h| h.to_s.strip.downcase.gsub(/\s+/, '_') }

    # Skip meta/descriptor rows (Required/Optional row, description row from template)
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

      # Skip blank rows
      next if row_data.values.all? { |v| v.to_s.strip.blank? }

      begin
        result = process_row(row_data, import.organisation)
        if result == :updated
          update_count  += 1
          success_count += 1
        else
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
    # ── Category (case-insensitive match) ──
    category_name = row['category'].to_s.strip
    raise "Missing category" if category_name.blank?
    category = ProductCategory.where('LOWER(name) = LOWER(?)', category_name).first
    raise "Category '#{category_name}' not found" unless category

    # ── UOM — try short_name then full name (case-insensitive) ──
    uom_val = row['uom'].to_s.strip
    raise "Missing UOM" if uom_val.blank?
    uom = Uom.where('LOWER(short_name) = LOWER(?)', uom_val).first ||
          Uom.where('LOWER(name) = LOWER(?)', uom_val).first
    raise "UOM '#{uom_val}' not found" unless uom

    # ── Import key — which field identifies existing records ──
    import_key = if ProductCategory.column_names.include?('import_key')
                   category.import_key.presence || 'material_code'
                 else
                   'material_code'
                 end

    import_value = row[import_key].to_s.strip

    # ── Find existing product (case-insensitive, trimmed) ──
    existing = nil
    if import_value.present?
      existing = Product.where("LOWER(TRIM(#{import_key})) = LOWER(?)", import_value.downcase).first
    end

    attrs = build_attrs(row, category, uom)

    if existing
      existing.assign_attributes(attrs)
      raise existing.errors.full_messages.join(', ') unless existing.valid?
      existing.save!
      :updated
    else
      product = Product.new(attrs)
      raise product.errors.full_messages.join(', ') unless product.valid?
      product.save!
      :created
    end
  end

  def build_attrs(row, category, uom)
    gst_raw = row['gst_rate'].to_s.strip.gsub('%', '')
    gst     = gst_raw.present? ? gst_raw.to_f : 18.0

    active_val = row['active'].to_s.strip.downcase
    active     = !%w[false 0 no inactive].include?(active_val)

    attrs = {
      product_category: category,
      base_uom:         uom,
      brand:            row['brand'].to_s.strip,
      pack_code:        row['pack_code'].to_s.strip.presence,
      description:      row['description'].to_s.strip,
      material_code:    row['material_code'].to_s.strip.presence,
      product_code:     row['product_code'].to_s.strip.presence,
      hsn_code:         row['hsn_code'].to_s.strip.presence,
      gst_rate:         gst,
      active:           active
    }

    if Product.column_names.include?('mrp')
      mrp_raw  = row['mrp'].to_s.strip
      attrs[:mrp] = mrp_raw.present? ? mrp_raw.to_f : nil
    end

    attrs
  end
end