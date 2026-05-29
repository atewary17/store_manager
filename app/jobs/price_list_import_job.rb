require 'roo'
require 'base64'

class PriceListImportJob < ApplicationJob
  queue_as :default

  CODE_HEADERS = %w[prod_code product_code shade_code pack_code].freeze

  def perform(price_list_import_id)
    import = PriceListImport.find(price_list_import_id)
    import.update!(status: 'processing')

    file_data = Base64.decode64(import.file_data)
    tmp = Tempfile.new(['price_list', '.xlsx'])
    tmp.binmode
    tmp.write(file_data)
    tmp.flush

    xlsx = Roo::Excelx.new(tmp.path)
    xlsx.default_sheet = xlsx.sheets.first
    sheet = xlsx.sheet(0)

    raw_headers = sheet.row(1)
    headers     = raw_headers.map { |h| normalise_header(h) }
    col_index   = headers.each_with_index.to_h { |h, i| [h, i + 1] }

    data_start = 2
    (2..4).each do |r|
      first = sheet.cell(r, 1).to_s.strip.downcase
      if first.in?(%w[required optional]) ||
         first.start_with?('brand', 'for ref', 'must', 'full product', 'human')
        data_start = r + 1
      else
        break
      end
    end

    brand_cache = Brand.all.index_by { |b| b.name.downcase.strip }

    created  = 0
    updated  = 0
    skipped  = 0
    errors   = []
    now      = Time.current

    (data_start..sheet.last_row).each do |row_num|
      row_values = sheet.row(row_num)
      next if row_values.all? { |v| v.to_s.strip.blank? }

      row_data = headers.zip(row_values).to_h.with_indifferent_access

      CODE_HEADERS.each do |key|
        next unless col_index.key?(key)
        raw = begin
          xlsx.formatted_value(row_num, col_index[key])
        rescue => _e
          xlsx.cell(row_num, col_index[key])
        end
        row_data[key] = raw.to_s.strip
      end

      base_name    = plain_text(row_data[:product_base_name]).presence ||
                     plain_text(row_data[:product_name]).presence
      raw_price    = plain_text(row_data[:dealer_price])

      next if base_name.blank? || raw_price.blank?
      next unless raw_price.gsub(/[,\s]/, '').match?(/\A\d[\d.]*\z/)

      dealer_price = raw_price.gsub(',', '').to_f

      row_date = plain_text(row_data[:effective_date]).presence
      eff_date = row_date.present? ? parse_date(row_date) : import.effective_date

      prod_code  = plain_text(row_data[:prod_code]).presence ||
                   plain_text(row_data[:product_code]).presence
      shade_code = plain_text(row_data[:shade_code]).presence
      pack_code  = plain_text(row_data[:pack_code]).presence

      brand_name = plain_text(row_data[:brand])
      brand      = brand_cache[brand_name.downcase] if brand_name.present?

      existing = PriceListRow.find_by(
        product_base_name: base_name,
        prod_code:         prod_code,
        shade_code:        shade_code,
        pack_code:         pack_code,
        effective_date:    eff_date
      )

      if existing
        existing.update!(
          dealer_price:     dealer_price,
          brand_id:         brand&.id,
          dpl_group:        plain_text(row_data[:dpl_group]).presence&.to_i || existing.dpl_group,
          pack_size_litres: parse_decimal(row_data[:pack_size_litres]) || existing.pack_size_litres,
          shade_name:       plain_text(row_data[:shade_name]).presence || existing.shade_name
        )
        updated += 1
      else
        PriceListRow.create!(
          brand_id:          brand&.id,
          product_base_name: base_name,
          prod_code:         prod_code,
          shade_name:        plain_text(row_data[:shade_name]).presence,
          shade_code:        shade_code,
          dpl_group:         plain_text(row_data[:dpl_group]).presence&.to_i,
          pack_size_litres:  parse_decimal(row_data[:pack_size_litres]),
          pack_code:         pack_code,
          dealer_price:      dealer_price,
          effective_date:    eff_date,
          match_status:      'pending',
          imported_at:       now
        )
        created += 1
      end

    rescue ActiveRecord::RecordInvalid => e
      errors << { 'row' => row_num, 'product_base_name' => base_name.to_s,
                  'prod_code' => prod_code.to_s, 'error' => e.message }
      skipped += 1
    end

    import.update!(
      status:        'done',
      total_rows:    created + updated + skipped + errors.size,
      success_count: created,
      update_count:  updated,
      skip_count:    skipped,
      error_count:   errors.size,
      error_rows:    errors,
      completed_at:  Time.current
    )

  rescue => e
    import.update!(
      status:       'failed',
      error_count:  1,
      error_rows:   [{ 'error' => e.message }],
      completed_at: Time.current
    )
  ensure
    tmp&.close
    tmp&.unlink
  end

  private

  def normalise_header(h)
    plain_text(h).downcase.gsub(/[^a-z0-9]+/, '_').squeeze('_').delete_suffix('_')
  end

  def plain_text(val)
    val.to_s.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
  end

  def parse_date(str)
    Date.parse(str.to_s)
  rescue ArgumentError
    Date.today
  end

  def parse_decimal(val)
    return nil if val.to_s.strip.blank?
    val.to_s.gsub(',', '').to_f.presence
  end
end
