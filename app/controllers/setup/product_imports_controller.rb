# app/controllers/setup/product_imports_controller.rb
require 'axlsx'
require 'base64'

class Setup::ProductImportsController < Setup::BaseController
  def index
    @product_imports = @imports = ProductImport.for_org(@organisation).recent.limit(50)
    @shade_imports   = if current_user.super_admin? &&
                            ActiveRecord::Base.connection.table_exists?(:shade_catalogue_imports)
                          ShadeCatalogueImport.where(organisation: @organisation)
                                              .order(created_at: :desc).limit(50)
                        else
                          []
                        end
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
                   material_code product_code hsn_code gst_rate
                   mrp internal_code local_description active]
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
    # Text format — forces Excel to keep leading zeros on code fields
    txt_hdr      = styles.add_style(bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11,
                     border: { style: :thin, color: 'FFFFFF' },
                     alignment: { horizontal: :center, vertical: :center, wrap_text: true },
                     format_code: '@')
    txt_example  = styles.add_style(bg_color: 'F2F2F2', fg_color: '404040', sz: 10,
                     i: true, format_code: '@')

    # Metadata style — distinct dark teal header for meta columns
    meta_hdr = styles.add_style(bg_color: '1D4E4E', fg_color: 'FFFFFF', b: true, sz: 10,
                 border: { style: :thin, color: 'FFFFFF' },
                 alignment: { horizontal: :center, vertical: :center, wrap_text: true })
    meta_opt = styles.add_style(bg_color: 'E2F0EF', fg_color: '1D4E4E', sz: 10,
                 alignment: { horizontal: :center, wrap_text: true })
    meta_desc = styles.add_style(bg_color: 'EAF4F4', fg_color: '1D4E4E', sz: 9,
                  alignment: { wrap_text: true, vertical: :top })
    meta_ex  = styles.add_style(bg_color: 'F0FAFA', fg_color: '404040', sz: 10, i: true)

    wb.add_worksheet(name: 'Products') do |sheet|

      # ── Row 1: Column headers ──
      sheet.add_row(
        # Core fields
        ['category', 'uom', 'brand', 'pack_code', 'description',
         'material_code', 'product_code', 'hsn_code', 'gst_rate',
         'mrp', 'internal_code', 'local_description', 'active',
         # Metadata fields
         'meta:tint', 'meta:family_colour', 'meta:canister_volume_ml',
         'meta:source', 'meta:validation_status', 'meta:ai_confidence',
         'meta:ai_brand_guess', 'meta:ai_category_guess', 'meta:ai_notes',
         'meta:original_name'],
        style: [hdr, hdr, hdr, hdr, hdr,
                txt_hdr, txt_hdr, txt_hdr, hdr,
                hdr, hdr, hdr, hdr,
                meta_hdr, meta_hdr, meta_hdr,
                meta_hdr, meta_hdr, meta_hdr,
                meta_hdr, meta_hdr, meta_hdr, meta_hdr],
        height: 28
      )

      # ── Row 2: Required / Optional ──
      sheet.add_row(
        ['REQUIRED', 'REQUIRED', 'REQUIRED', 'optional', 'REQUIRED',
         'optional*', 'optional*', 'optional', 'REQUIRED',
         'optional', 'optional', 'optional', 'REQUIRED',
         'optional', 'optional', 'optional',
         'optional', 'optional', 'optional',
         'optional', 'optional', 'optional', 'optional'],
        style: [req, req, req, opt, req, opt, opt, opt, req,
                opt, opt, opt, req,
                meta_opt, meta_opt, meta_opt,
                meta_opt, meta_opt, meta_opt,
                meta_opt, meta_opt, meta_opt, meta_opt],
        height: 20
      )

      # ── Row 3: Field descriptions ──
      sheet.add_row(
        [
          'Must match an existing Category name exactly',
          'UOM short name e.g. Ltr / Kg / Pcs / Mtr',
          'Brand name (text)',
          'Pack size e.g. 1L / 500ml / 20Kg',
          'Full product description (text)',
          'Material code — unique import key (*)',
          'Product code — optional import key (*)',
          'HSN code for GST (text)',
          'GST rate: 0 / 5 / 12 / 18 / 28',
          'Your org MRP — stored per organisation only',
          'Your internal shelf/SKU code — org only',
          'Your description override — org only',
          'true = active  |  false = inactive',
          # Meta descriptions
          'true = colorant for tinting machine',
          'Colour family e.g. Red Oxide, Burnt Amber',
          'Volume in ml e.g. 500, 1000',
          'Leave blank or: ai_enrichment',
          'pending / approved / needs_validation',
          'AI confidence 0.0–1.0',
          'Brand name guessed by AI',
          'Category name guessed by AI',
          'Notes from AI enrichment',
          'Original product name from invoice'
        ],
        style: [desc, desc, desc, desc, desc, desc, desc, desc, desc,
                desc, desc, desc, desc,
                meta_desc, meta_desc, meta_desc,
                meta_desc, meta_desc, meta_desc,
                meta_desc, meta_desc, meta_desc, meta_desc],
        height: 48
      )

      # ── Row 4–6: Example data ──
      sheet.add_row(
        ['Paints', 'Ltr', 'Asian Paints', '1L', 'Tractor Emulsion Interior',
         'AP-EMU-1L', 'PROD-001', '3208', '18', '450.00', 'SH-001', '', 'true',
         '', '', '', '', '', '', '', '', '', ''],
        style: [example, example, example, example, example,
                txt_example, txt_example, txt_example, example,
                example, example, example, example,
                meta_ex, meta_ex, meta_ex, meta_ex, meta_ex,
                meta_ex, meta_ex, meta_ex, meta_ex, meta_ex],
        height: 18
      )
      sheet.add_row(
        ['Paints', 'Ltr', 'Asian Paints', '200ml',
         'APCO Gloss Enamel Gold 200ML',
         '0001M003120', '', '3209', '18', '95.00', '', '', 'true',
         'true', 'Gold Oxide', '200', '', '', '', '', '', '', ''],
        style: [example, example, example, example, example,
                txt_example, txt_example, txt_example, example,
                example, example, example, example,
                meta_ex, meta_ex, meta_ex, meta_ex, meta_ex,
                meta_ex, meta_ex, meta_ex, meta_ex, meta_ex],
        height: 18
      )
      sheet.add_row(
        ['Pipes & Fittings', 'Mtr', 'Supreme', '6m', 'UPVC Column Pipe 4 inch',
         '', 'SP-UPVC-6M', '3917', '12', '180.00', '', 'Supreme 4" column pipe 6m', 'true',
         '', '', '', '', '', '', '', '', '', ''],
        style: [example, example, example, example, example,
                txt_example, txt_example, txt_example, example,
                example, example, example, example,
                meta_ex, meta_ex, meta_ex, meta_ex, meta_ex,
                meta_ex, meta_ex, meta_ex, meta_ex, meta_ex],
        height: 18
      )

      # Column widths: core 13 cols + 10 metadata cols
      sheet.column_widths 24, 12, 18, 12, 34, 20, 20, 12, 10, 12, 18, 28, 12,
                          14, 20, 18, 16, 20, 14, 18, 20, 28, 24
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
      sheet.add_row ['']
      sheet.add_row ['METADATA COLUMNS (teal headers)'], style: h, height: 22
      sheet.add_row ['• Metadata columns are prefixed with "meta:" — e.g. meta:tint, meta:family_colour'], style: b, height: 18
      sheet.add_row ['• All metadata columns are optional — leave blank to skip'], style: b, height: 18
      sheet.add_row ['• On UPDATE, existing metadata is merged — only keys present in the file are overwritten'], style: b, height: 18
      sheet.add_row ['']
      sheet.add_row ['TINTING MACHINE METADATA'], style: h, height: 22
      sheet.add_row ['meta:tint             → true = this product is a colorant for the tinting machine'], style: cd, height: 16
      sheet.add_row ['meta:family_colour    → colour family name shown in tinting machine UI (e.g. Red Oxide)'], style: cd, height: 16
      sheet.add_row ['meta:canister_volume_ml → default volume in ml when loaded into machine (e.g. 1000)'], style: cd, height: 16
      sheet.add_row ['']
      sheet.add_row ['AI ENRICHMENT METADATA (auto-set by AI — edit only if needed)'], style: h, height: 22
      sheet.add_row ['meta:source             → ai_enrichment (set automatically, do not change)'], style: cd, height: 16
      sheet.add_row ['meta:validation_status  → pending / approved / needs_validation'],            style: cd, height: 16
      sheet.add_row ['meta:ai_confidence      → 0.0 to 1.0 confidence score from AI'],             style: cd, height: 16
      sheet.add_row ['meta:original_name      → original product name from the purchase invoice'], style: cd, height: 16
      sheet.add_row ['']
      sheet.add_row ['CUSTOM METADATA'], style: h, height: 22
      sheet.add_row ['• You can add your own columns with the meta: prefix for custom attributes'], style: b, height: 18
      sheet.add_row ['• Example: meta:colour_code, meta:finish_type, meta:supplier_sku'], style: b, height: 18
      sheet.add_row ['• Custom meta: columns are imported automatically — no configuration needed'], style: b, height: 18

      sheet.column_widths 72
    end

    package.to_stream.read
  end
end