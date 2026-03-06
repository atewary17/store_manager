# app/jobs/shade_catalogue_import_job.rb
require 'roo'
require 'base64'

class ShadeCatalogueImportJob < ApplicationJob
  queue_as :default

  def perform(shade_catalogue_import_id)
    import = ShadeCatalogueImport.find(shade_catalogue_import_id)
    import.update!(status: 'processing')

    # Decode and write to tempfile
    file_data = Base64.decode64(import.file_data)
    tmp = Tempfile.new(['shade_import', '.xlsx'])
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
      break if r > sheet.last_row
      first_cell = sheet.row(r).first.to_s.strip.downcase
      if %w[required optional required*].any? { |s| first_cell.start_with?(s) } ||
         first_cell.include?('must match') || first_cell.include?('manufacturer shade') ||
         first_cell.include?('full shade') || first_cell.include?('brand name')
        data_start = r + 1
      else
        break
      end
    end

    total_rows = sheet.last_row - (data_start - 1)
    import.update!(total_rows: [total_rows, 0].max)

    category      = import.product_category
    success_count = 0
    update_count  = 0
    error_count   = 0
    error_rows    = []

    (data_start..sheet.last_row).each do |row_num|
      row_data = headers.zip(sheet.row(row_num)).to_h.with_indifferent_access

      # Skip blank rows
      next if row_data.values.all? { |v| v.to_s.strip.blank? }

      begin
        result = process_row(row_data, category)
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

  def process_row(row, category)
    # ── Shade code (required) ──
    shade_code = row['shade_code'].to_s.strip
    raise "Missing shade_code" if shade_code.blank?

    # ── Shade name (required) ──
    shade_name = row['shade_name'].to_s.strip
    raise "Missing shade_name" if shade_name.blank?

    # ── Brand / Manufacturer (optional — match by name) ──
    brand = nil
    manufacturer_val = row['manufacturer'].to_s.strip
    if manufacturer_val.present?
      brand = Brand.where('LOWER(name) = LOWER(?)', manufacturer_val).first
      # Don't fail if brand not found — just leave it nil
    end

    # ── Optional fields ──
    colour_family = row['colour_family'].to_s.strip.presence
    notes         = row['notes'].to_s.strip.presence

    active_val = row['active'].to_s.strip.downcase
    active = if active_val.blank?
               true
             else
               !%w[false 0 no inactive].include?(active_val)
             end

    # ── Upsert by shade_code + category (case-insensitive) ──
    existing = ShadeCatalogue.where(product_category: category)
                             .where('LOWER(TRIM(shade_code)) = LOWER(?)', shade_code.downcase)
                             .first

    attrs = {
      product_category: category,
      shade_code:       shade_code,
      shade_name:       shade_name,
      brand:            brand,
      colour_family:    colour_family,
      notes:            notes,
      active:           active
    }

    if existing
      existing.assign_attributes(attrs)
      raise existing.errors.full_messages.join(', ') unless existing.valid?
      existing.save!
      :updated
    else
      shade = ShadeCatalogue.new(attrs)
      raise shade.errors.full_messages.join(', ') unless shade.valid?
      shade.save!
      :created
    end
  end
end
