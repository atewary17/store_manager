# app/controllers/setup/product_imports_controller.rb
require 'axlsx'
require 'base64'

class Setup::ProductImportsController < Setup::BaseController
  def index
    @imports = ProductImport.recent.limit(50)
  end

  def new
    @import    = ProductImport.new
    @categories = ProductCategory.active.ordered
  end

  def create
    file = params[:file]

    unless file.present? && file.content_type.in?(valid_mime_types)
      redirect_to new_setup_product_import_path, alert: 'Please upload a valid .xlsx file.'
      return
    end

    import = ProductImport.create!(
      organisation: current_user.organisation,
      user:         current_user,
      file_name:    file.original_filename,
      file_size:    file.size,
      status:       'pending',
      file_data:    Base64.encode64(file.read)
    )

    ProductImportJob.perform_later(import.id)

    redirect_to setup_product_imports_path,
      notice: "Import started — #{file.original_filename} is being processed in the background."
  end

  def show
    @import = ProductImport.find(params[:id])
  end

  def download_errors
    @import = ProductImport.find(params[:id])

    unless @import.has_errors?
      redirect_to setup_product_import_path(@import), alert: 'No errors to download.'
      return
    end

    send_data generate_error_report(@import),
      filename:    "import_errors_#{@import.id}_#{Date.today}.xlsx",
      type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition: 'attachment'
  end

  def template
    send_data generate_template,
      filename:    'product_import_template.xlsx',
      type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition: 'attachment'
  end

  private

  def valid_mime_types
    [
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-excel',
      'application/octet-stream'
    ]
  end

  def generate_error_report(import)
    package = Axlsx::Package.new
    wb      = package.workbook

    wb.add_worksheet(name: 'Import Errors') do |sheet|
      headers = %w[row_number error category uom brand pack_code description
                   material_code product_code hsn_code gst_rate mrp active]
      sheet.add_row headers
      import.error_rows.each do |row|
        sheet.add_row headers.map { |h| row[h].to_s }
      end
    end

    package.to_stream.read
  end

  def generate_template
    package = Axlsx::Package.new
    wb      = package.workbook

    # Define all styles upfront as local variables
    styles       = wb.styles
    hdr          = styles.add_style(bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11,
                     border: { style: :thin, color: 'FFFFFF' },
                     alignment: { horizontal: :center, vertical: :center, wrap_text: true })
    req          = styles.add_style(bg_color: 'FCE4D6', fg_color: 'C00000', b: true, sz: 10,
                     alignment: { horizontal: :center, wrap_text: true })
    opt          = styles.add_style(bg_color: 'E2EFDA', fg_color: '375623', sz: 10,
                     alignment: { horizontal: :center, wrap_text: true })
    desc         = styles.add_style(bg_color: 'FFF2CC', fg_color: '7F6000', sz: 9,
                     alignment: { wrap_text: true, vertical: :top })
    example      = styles.add_style(bg_color: 'F2F2F2', fg_color: '404040', sz: 10, i: true)
    example_bold = styles.add_style(bg_color: 'F2F2F2', fg_color: '404040', sz: 10, b: true)

    wb.add_worksheet(name: 'Products') do |sheet|

      # ── Row 1: Column headers ──
      sheet.add_row(
        ['category', 'uom', 'brand', 'pack_code', 'description',
         'material_code', 'product_code', 'hsn_code', 'gst_rate', 'mrp', 'active'],
        style: hdr, height: 28
      )

      # ── Row 2: Required / Optional ──
      sheet.add_row(
        ['REQUIRED', 'REQUIRED', 'REQUIRED', 'optional', 'REQUIRED',
         'optional*', 'optional*', 'optional', 'REQUIRED', 'optional', 'REQUIRED'],
        style: [req, req, req, opt, req, opt, opt, opt, req, opt, req],
        height: 20
      )

      # ── Row 3: Field descriptions ──
      sheet.add_row(
        [
          'Must match an existing Category name exactly (case-sensitive)',
          'UOM short name e.g. Ltr / Kg / Pcs / Mtr',
          'Brand name (text)',
          'Pack size e.g. 1L / 500ml / 20Kg',
          'Full product description (text)',
          'Material code — used as import key for Paints (*)',
          'Product code — used as import key if configured (*)',
          'HSN code for GST (text)',
          'GST rate: must be one of 0 / 5 / 12 / 18 / 28',
          'Max Retail Price — decimal e.g. 450.00',
          'true = active  |  false = inactive'
        ],
        style: desc, height: 48
      )

      # ── Row 4–6: Example data ──
      sheet.add_row(
        ['Paints', 'Ltr', 'Asian Paints', '1L', 'Tractor Emulsion Interior',
         'AP-EMU-1L', 'PROD-001', '3208', '18', '450.00', 'true'],
        style: example, height: 18
      )
      sheet.add_row(
        ['Paints', 'Kg', 'Berger', '20Kg', 'Weathercoat Exterior',
         'BG-WC-20K', 'PROD-002', '3208', '18', '2800.00', 'true'],
        style: example, height: 18
      )
      sheet.add_row(
        ['Pipes & Fittings', 'Mtr', 'Supreme', '6m', 'UPVC Column Pipe 4 inch',
         '', 'SP-UPVC-6M', '3917', '12', '180.00', 'true'],
        style: example, height: 18
      )

      # Column widths (characters)
      sheet.column_widths 24, 12, 18, 12, 34, 20, 20, 12, 10, 12, 12
    end

    # ── Instructions sheet ──
    wb.add_worksheet(name: 'Instructions') do |sheet|
      t  = styles.add_style(b: true, sz: 14, fg_color: '1F3864')
      h  = styles.add_style(b: true, sz: 11, fg_color: '1F3864')
      b  = styles.add_style(sz: 10, alignment: { wrap_text: true })
      cd = styles.add_style(sz: 10, font_name: 'Courier New', bg_color: 'F2F2F2', fg_color: '404040')

      sheet.add_row ['StoreERP — Product Import Guide'], style: t, height: 32
      sheet.add_row ['']
      sheet.add_row ['GENERAL RULES'], style: h, height: 22
      sheet.add_row ['• Do NOT change column headers in row 1 of the Products sheet'], style: b, height: 18
      sheet.add_row ['• Rows 2 and 3 are for your reference — you may delete them before uploading'], style: b, height: 18
      sheet.add_row ['• The system processes each row individually — one bad row will not stop others'], style: b, height: 18
      sheet.add_row ['']
      sheet.add_row ['HOW UPDATES WORK (Import Key)'], style: h, height: 22
      sheet.add_row ['• Each category has a configured "import key" field (set in Setup → Product Categories)'], style: b, height: 18
      sheet.add_row ['• On upload, if a product with that key value exists → it is UPDATED'], style: b, height: 18
      sheet.add_row ['• If no match → a new product is CREATED'], style: b, height: 18
      sheet.add_row ['• (*) material_code is the default import key. Configure per-category in Setup.'], style: b, height: 18
      sheet.add_row ['']
      sheet.add_row ['GST RATE — ALLOWED VALUES ONLY'], style: h, height: 22
      sheet.add_row ['0    → 0% (exempt)'], style: cd, height: 16
      sheet.add_row ['5    → 5%'],           style: cd, height: 16
      sheet.add_row ['12   → 12%'],          style: cd, height: 16
      sheet.add_row ['18   → 18%'],          style: cd, height: 16
      sheet.add_row ['28   → 28%'],          style: cd, height: 16
      sheet.add_row ['']
      sheet.add_row ['ACTIVE FIELD'], style: h, height: 22
      sheet.add_row ['true   → product is visible and usable in transactions'], style: cd, height: 16
      sheet.add_row ['false  → product is hidden (soft-disabled)'],             style: cd, height: 16

      sheet.column_widths 72
    end

    package.to_stream.read
  end
end