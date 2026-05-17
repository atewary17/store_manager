# app/controllers/setup/price_list_rows_controller.rb
require 'axlsx'
require 'base64'

class Setup::PriceListRowsController < Setup::BaseController

  before_action :require_super_admin!
  before_action :set_row,    only: [:show, :edit, :update]
  before_action :set_import, only: [:import_show, :download_errors]

  PER_PAGE = 50

  # ── Index ─────────────────────────────────────────────────────
  def index
    @rows = PriceListRow.all.ordered

    if params[:status].present? && PriceListRow::MATCH_STATUSES.include?(params[:status])
      @rows = @rows.where(match_status: params[:status])
    end

    @rows = @rows.for_date(params[:date]) if params[:date].present?
    @rows = @rows.search(params[:q])      if params[:q].present?

    @total_count     = PriceListRow.count
    @pending_count   = PriceListRow.pending.count
    @matched_count   = PriceListRow.matched.count
    @unmatched_count = PriceListRow.unmatched.count
    @ambiguous_count = PriceListRow.ambiguous.count

    @filtered_count = @rows.count
    @page           = [params[:page].to_i, 1].max
    @total_pages    = [(@filtered_count.to_f / PER_PAGE).ceil, 1].max
    @page           = [@page, @total_pages].min
    @rows           = @rows.includes(:brand, :matched_product)
                           .offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

    @effective_dates = PriceListRow.distinct.order(effective_date: :desc).pluck(:effective_date)
  end

  # ── Show ──────────────────────────────────────────────────────
  def show
  end

  # ── Edit ──────────────────────────────────────────────────────
  def edit
    @brands = Brand.active.ordered
  end

  # ── Update ────────────────────────────────────────────────────
  def update
    if @row.update(row_params)
      redirect_to setup_price_list_row_path(@row),
        notice: 'Price list row updated successfully.'
    else
      @brands = Brand.active.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  # ── Import (GET) ──────────────────────────────────────────────
  def import
    @effective_dates   = PriceListRow.distinct.order(effective_date: :desc).pluck(:effective_date)
    @recent_imports    = PriceListImport.recent.includes(:user).limit(20)
  end

  # ── Import (POST) ─────────────────────────────────────────────
  def import_create
    file           = params[:file]
    effective_date = params[:effective_date].presence

    unless file.present? && file.content_type.in?(valid_mime_types)
      redirect_to import_setup_price_list_rows_path,
        alert: 'Please upload a valid .xlsx file.'
      return
    end

    unless effective_date.present?
      redirect_to import_setup_price_list_rows_path,
        alert: 'Please select an effective date for this price list.'
      return
    end

    import = PriceListImport.create!(
      user:           current_user,
      file_name:      file.original_filename,
      file_size:      file.size,
      effective_date: effective_date,
      status:         'pending',
      file_data:      Base64.strict_encode64(file.read)
    )

    PriceListImportJob.perform_later(import.id)

    redirect_to import_show_setup_price_list_rows_path(import),
      notice: 'Import queued — processing in background. This page will refresh automatically.'
  end

  # ── Import show ───────────────────────────────────────────────
  def import_show
  end

  # ── Download errors ───────────────────────────────────────────
  def download_errors
    unless @import.has_errors?
      redirect_to import_show_setup_price_list_rows_path(@import), alert: 'No errors to download.'
      return
    end

    send_data generate_error_xlsx(@import),
      filename:    "price_list_import_errors_#{@import.id}_#{Date.today}.xlsx",
      type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition: 'attachment'
  end

  # ── Export ────────────────────────────────────────────────────
  def export
    rows = PriceListRow.ordered.includes(:brand)
    rows = rows.for_date(params[:date]) if params[:date].present?

    send_data generate_export(rows),
      filename:    "price_list_#{params[:date].presence || Date.today.strftime('%Y%m%d')}.xlsx",
      type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition: 'attachment'
  end

  # ── Template ──────────────────────────────────────────────────
  def template
    send_data generate_template,
      filename:    'price_list_import_template.xlsx',
      type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition: 'attachment'
  end

  private

  def set_row
    @row = PriceListRow.includes(:brand, :matched_product).find(params[:id])
  end

  def set_import
    @import = PriceListImport.includes(:user).find(params[:id])
  end

  def require_super_admin!
    unless current_user.super_admin?
      redirect_to setup_root_path, alert: 'Access denied.'
    end
  end

  def row_params
    params.require(:price_list_row).permit(
      :brand_id, :product_base_name, :prod_code,
      :shade_name, :shade_code, :dpl_group,
      :pack_size_litres, :pack_code,
      :dealer_price, :effective_date,
      :match_status, :matched_product_id
    )
  end

  def valid_mime_types
    %w[
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      application/vnd.ms-excel
      application/octet-stream
    ]
  end

  # ── Error report XLSX ─────────────────────────────────────────
  def generate_error_xlsx(import)
    package = Axlsx::Package.new
    wb      = package.workbook
    hdr     = wb.styles.add_style(b: true, sz: 10, bg_color: '1F3864', fg_color: 'FFFFFF')
    txt     = wb.styles.add_style(format_code: '@', sz: 10)
    reg     = wb.styles.add_style(sz: 10)
    err     = wb.styles.add_style(sz: 10, fg_color: 'C00000')

    wb.add_worksheet(name: 'Import Errors') do |sheet|
      headers = %w[row product_base_name prod_code shade_code effective_date error]
      sheet.add_row headers, style: hdr
      import.error_rows.each do |row|
        sheet.add_row(
          headers.map { |h| row[h].to_s },
          style: [reg, reg, txt, txt, reg, err],
          types: [nil, nil, :string, :string, nil, nil]
        )
      end
    end

    package.to_stream.read
  end

  # ── Export XLSX ───────────────────────────────────────────────
  def generate_export(rows)
    package = Axlsx::Package.new
    wb      = package.workbook
    styles  = wb.styles

    hdr  = styles.add_style(bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11,
             alignment: { horizontal: :center, vertical: :center })
    txt  = styles.add_style(format_code: '@', sz: 10)
    even = styles.add_style(bg_color: 'F7F9FC', fg_color: '404040', sz: 10)
    odd  = styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10)
    num  = styles.add_style(fg_color: '404040', sz: 10, alignment: { horizontal: :right })
    stm  = styles.add_style(bg_color: 'E8F5E9', fg_color: '2E7D32', sz: 10,
             alignment: { horizontal: :center })
    stp  = styles.add_style(bg_color: 'FFF8E1', fg_color: 'F57F17', sz: 10,
             alignment: { horizontal: :center })
    stu  = styles.add_style(bg_color: 'FFEBEE', fg_color: 'C62828', sz: 10,
             alignment: { horizontal: :center })
    sta  = styles.add_style(bg_color: 'F5F5F5', fg_color: '757575', sz: 10,
             alignment: { horizontal: :center })

    wb.add_worksheet(name: 'Price List') do |sheet|
      sheet.add_row(
        %w[brand product_base_name prod_code shade_name shade_code dpl_group
           pack_size_litres pack_code dealer_price effective_date
           match_status matched_product_id],
        style: Array.new(12, hdr), height: 24
      )

      rows.each_with_index do |row, i|
        rs = i.even? ? even : odd
        st = case row.match_status
             when 'matched'   then stm
             when 'pending'   then stp
             when 'unmatched' then stu
             else sta
             end

        sheet.add_row([
          row.brand&.name.to_s,
          row.product_base_name,
          row.prod_code.to_s,
          row.shade_name.to_s,
          row.shade_code.to_s,
          row.dpl_group,
          row.pack_size_litres,
          row.pack_code.to_s,
          row.dealer_price,
          row.effective_date.to_s,
          row.match_status,
          row.matched_product_id
        ], style: [rs, rs, txt, rs, txt, rs, num, txt, num, rs, st, rs],
           types: [nil, nil, :string, nil, :string, nil, nil, :string, nil, nil, nil, nil],
           height: 18)
      end

      sheet.column_widths 18, 40, 12, 20, 14, 10, 14, 12, 14, 14, 14, 16
    end

    package.to_stream.read
  end

  # ── Import template ───────────────────────────────────────────
  def generate_template
    package = Axlsx::Package.new
    wb      = package.workbook
    styles  = wb.styles

    hdr     = styles.add_style(bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11,
                border: { style: :thin, color: 'FFFFFF' },
                alignment: { horizontal: :center, vertical: :center, wrap_text: true })
    txt_hdr = styles.add_style(bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11,
                border: { style: :thin, color: 'FFFFFF' },
                alignment: { horizontal: :center, vertical: :center, wrap_text: true },
                format_code: '@')
    req     = styles.add_style(bg_color: 'FCE4D6', fg_color: 'C00000', b: true, sz: 10,
                alignment: { horizontal: :center, wrap_text: true })
    opt     = styles.add_style(bg_color: 'E2EFDA', fg_color: '375623', sz: 10,
                alignment: { horizontal: :center, wrap_text: true })
    desc    = styles.add_style(bg_color: 'FFF2CC', fg_color: '7F6000', sz: 9,
                alignment: { wrap_text: true, vertical: :top })
    ex      = styles.add_style(bg_color: 'F2F2F2', fg_color: '404040', sz: 10, i: true)
    txt_ex  = styles.add_style(bg_color: 'F2F2F2', fg_color: '404040', sz: 10,
                i: true, format_code: '@')
    num_ex  = styles.add_style(bg_color: 'F2F2F2', fg_color: '404040', sz: 10,
                i: true, alignment: { horizontal: :right })

    col_headers = %w[brand product_base_name prod_code shade_name shade_code
                     dpl_group pack_size_litres pack_code dealer_price effective_date]

    req_row    = ['optional', 'REQUIRED', 'optional', 'optional', 'optional',
                  'optional', 'optional', 'optional', 'REQUIRED', 'optional']
    req_styles = [opt, req, opt, opt, opt, opt, opt, opt, req, opt]

    desc_row = [
      'Brand name — matched to system brands (case-insensitive)',
      'Full product line name as it appears on the price list',
      '4-digit product code — stored as text e.g. 0026',
      'Human-readable shade name e.g. Brilliant White',
      'Shade code — stored as text e.g. 0912, 0W06',
      'Dealer price list group number e.g. 1, 2, 4',
      'Pack volume in litres e.g. 0.500, 1.000, 4.000',
      'Pack variant code — stored as text e.g. 150, 210, 320',
      'Dealer price as a number — no ₹ symbol or commas',
      'Leave blank to use the date entered on the import form (YYYY-MM-DD)'
    ]

    example_rows = [
      ['Asian Paints', 'ASIAN PAINTS APCOLITE PREMIUM GLOSS ENAMEL (W)', '0026',
       'Brilliant White', '0912', 1, 0.500, '150', 127.00, ''],
      ['Asian Paints', 'ASIAN PAINTS APCOLITE PREMIUM GLOSS ENAMEL (W)', '0026',
       'Blazing White', '0W06', 1, 1.000, '210', 243.00, ''],
      ['Asian Paints', 'ASIAN PAINTS APCOLITE PREMIUM GLOSS ENAMEL (W)', '0026',
       '', '', 1, 0.050, '050', 23.00, ''],
      ['Asian Paints', 'ASIAN PAINTS APCOLITE PREMIUM GLOSS ENAMEL (W)', '0026',
       '', '', 1, 0.100, '110', 37.00, ''],
    ]

    wb.add_worksheet(name: 'Price List') do |sheet|
      sheet.add_row(col_headers,
        style: [hdr, hdr, txt_hdr, hdr, txt_hdr, hdr, hdr, txt_hdr, hdr, hdr],
        height: 28)
      sheet.add_row(req_row, style: req_styles, height: 20)
      sheet.add_row(desc_row, style: Array.new(10, desc), height: 56)
      example_rows.each do |data|
        sheet.add_row(data,
          style: [ex, ex, txt_ex, ex, txt_ex, num_ex, num_ex, txt_ex, num_ex, ex],
          types: [nil, nil, :string, nil, :string, nil, nil, :string, nil, nil],
          height: 18)
      end
      sheet.column_widths 18, 46, 12, 22, 14, 10, 16, 12, 14, 16
    end

    wb.add_worksheet(name: 'Instructions') do |sheet|
      t = styles.add_style(b: true, sz: 14, fg_color: '1F3864')
      h = styles.add_style(b: true, sz: 11, fg_color: '1F3864')
      b = styles.add_style(sz: 10, alignment: { wrap_text: true })
      c = styles.add_style(sz: 10, font_name: 'Courier New',
            bg_color: 'F2F2F2', fg_color: '404040')

      sheet.add_row ['Price List Import Guide'], style: t, height: 32
      sheet.add_row ['']
      sheet.add_row ['COLUMN REFERENCE'], style: h, height: 22
      sheet.add_row ['brand              → matched to system brands (case-insensitive) — leave blank if unknown'], style: c, height: 16
      sheet.add_row ['product_base_name  → REQUIRED — full product line name from the price list'], style: c, height: 16
      sheet.add_row ['prod_code          → stored as text — leading zeros are preserved (e.g. 0026)'], style: c, height: 16
      sheet.add_row ['shade_name         → human-readable shade name e.g. "Brilliant White"'], style: c, height: 16
      sheet.add_row ['shade_code         → stored as text — e.g. "0912", "0W06"'], style: c, height: 16
      sheet.add_row ['dpl_group          → dealer price list group number (integer)'], style: c, height: 16
      sheet.add_row ['pack_size_litres   → pack volume in litres e.g. 0.500, 1.000, 4.000'], style: c, height: 16
      sheet.add_row ['pack_code          → stored as text — e.g. "050", "150", "320"'], style: c, height: 16
      sheet.add_row ['dealer_price       → REQUIRED — number only (no ₹ or commas)'], style: c, height: 16
      sheet.add_row ['effective_date     → optional — overrides the date on the import form (YYYY-MM-DD)'], style: c, height: 16
      sheet.add_row ['']
      sheet.add_row ['LEADING ZEROS — IMPORTANT'], style: h, height: 22
      sheet.add_row ['• prod_code, shade_code, and pack_code are stored as text'], style: b, height: 18
      sheet.add_row ['• Format these columns as TEXT in Excel to preserve leading zeros (e.g. "0026" not 26)'], style: b, height: 18
      sheet.add_row ['• In Excel: select the column → Format Cells → Text → then type or paste values'], style: b, height: 18
      sheet.add_row ['• This template already has these columns formatted as text'], style: b, height: 18
      sheet.add_row ['']
      sheet.add_row ['DUPLICATE HANDLING'], style: h, height: 22
      sheet.add_row ['• A row is a duplicate if product_base_name + prod_code + shade_code + pack_code + effective_date all match'], style: b, height: 18
      sheet.add_row ['• Duplicates are UPDATED — only the dealer_price, brand, dpl_group, pack_size_litres, and shade_name are refreshed'], style: b, height: 18
      sheet.add_row ['• match_status is NOT reset on update — use the matching job to re-run matching'], style: b, height: 18
      sheet.add_row ['']
      sheet.add_row ['BRAND MATCHING'], style: h, height: 22
      sheet.add_row ['• The brand column is matched case-insensitively to brands in the system'], style: b, height: 18
      sheet.add_row ['• If no match is found, brand_id is left blank (the row is still imported)'], style: b, height: 18
      sheet.add_row ['• Rows 2 and 3 in the data sheet are guide rows — delete them before uploading or leave them (the importer skips them)'], style: b, height: 18

      sheet.column_widths 90
    end

    package.to_stream.read
  end
end
