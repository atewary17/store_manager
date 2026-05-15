# app/controllers/setup/shade_catalogues_controller.rb
require 'axlsx'
require 'base64'

class Setup::ShadeCataloguesController < Setup::BaseController

  before_action :set_shade, only: [:show, :edit, :update, :destroy]

  # GET /setup/shade_catalogues
  def index
    @shades = ShadeCatalogue.includes(:product_category, :brand).ordered

    if params[:category_id].present?
      @shades = @shades.for_category(params[:category_id])
    end
    if params[:brand_id].present?
      @shades = @shades.for_brand(params[:brand_id])
    end
    if params[:q].present?
      @shades = @shades.search(params[:q])
    end
    if params[:status] == 'inactive'
      @shades = @shades.inactive
    else
      @shades = @shades.active
    end

    @shades = @shades.limit(20)

    @total_count    = ShadeCatalogue.count
    @active_count   = ShadeCatalogue.where(active: true).count
    @inactive_count = ShadeCatalogue.where(active: false).count

    @paint_categories = ProductCategory.paint_types.active.ordered
    @brands           = Brand.active.ordered
  end

  # GET /setup/shade_catalogues/new
  def new
    @shade = ShadeCatalogue.new
    @paint_categories = ProductCategory.paint_types.active.ordered
    @brands = Brand.active.ordered
  end

  # GET /setup/shade_catalogues/:id
  def show
  end

  # GET /setup/shade_catalogues/:id/edit
  def edit
    @paint_categories = ProductCategory.paint_types.active.ordered
    @brands = Brand.active.ordered
  end

  # POST /setup/shade_catalogues
  def create
    @shade = ShadeCatalogue.new(shade_params)
    if @shade.save
      redirect_to setup_shade_catalogues_path, notice: 'Shade added successfully.'
    else
      @paint_categories = ProductCategory.paint_types.active.ordered
      @brands = Brand.active.ordered
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH /setup/shade_catalogues/:id
  def update
    if @shade.update(shade_params)
      redirect_to setup_shade_catalogues_path, notice: 'Shade updated successfully.'
    else
      @paint_categories = ProductCategory.paint_types.active.ordered
      @brands = Brand.active.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /setup/shade_catalogues/:id
  def destroy
    if @shade.can_delete?
      @shade.destroy
      redirect_to setup_shade_catalogues_path, notice: 'Shade deleted.'
    else
      redirect_to setup_shade_catalogues_path, alert: 'Cannot delete — shade is used in sales invoices.'
    end
  end

  # GET /setup/shade_catalogues/template
  def template
    package = Axlsx::Package.new
    wb = package.workbook

    # Styles
    hdr     = wb.styles.add_style bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11, alignment: { wrap_text: false }
    req     = wb.styles.add_style bg_color: 'FEE2E2', fg_color: '991B1B', b: true, sz: 10, alignment: { wrap_text: false }
    opt     = wb.styles.add_style bg_color: 'DCFCE7', fg_color: '166534', b: true, sz: 10, alignment: { wrap_text: false }
    desc    = wb.styles.add_style bg_color: 'FEF9C3', fg_color: '713F12', sz: 9,  alignment: { wrap_text: true }
    example = wb.styles.add_style bg_color: 'F8FAFC', fg_color: '334155', sz: 10

    wb.add_worksheet(name: 'Shades') do |ws|
      ws.add_row(
        ['shade_code', 'shade_name', 'brand', 'product_family', 'colour_family', 'notes', 'active'],
        style: hdr
      )
      ws.add_row(
        ['Required*', 'Required*', 'Optional', 'Optional', 'Optional', 'Optional', 'Optional'],
        style: [req, req, opt, opt, opt, opt, opt]
      )
      ws.add_row(
        [
          'Manufacturer shade code. E.g. 7711, OW-120. Will be uppercased.',
          'Full shade name. E.g. Pastel Blue, Ivory White.',
          'Brand name. Must match an existing brand. E.g. Asian Paints, Berger.',
          'Product line / family. E.g. Apcolite Premium Gloss, Royale.',
          'Colour group for filtering. E.g. Blues, Whites, Neutrals.',
          'Any special notes. E.g. Interior use only.',
          'true or false. Defaults to true if blank.'
        ],
        style: desc
      )
      ws.add_row(['7711',  'Pastel Blue',    'Asian Paints', 'Apcolite Premium Gloss', 'Blues',   '',                    'true'],  style: example)
      ws.add_row(['OW-120','Ivory White',    'Berger',       'Breathe Easy',           'Whites',  'Interior use only',   'true'],  style: example)
      ws.add_row(['N-445', 'Terracotta Glow','Nerolac',      'Impressions',            'Oranges', '',                    'true'],  style: example)

      ws.column_widths 18, 24, 18, 26, 18, 30, 10
    end

    wb.add_worksheet(name: 'Instructions') do |ws|
      ws.add_row(['Shade Catalogue Import — Instructions'], style: hdr)
      ws.add_row([''])
      ws.add_row(['Field Rules:'])
      ws.add_row(['shade_code     — Required. Unique per category. Automatically uppercased on import.'])
      ws.add_row(['shade_name     — Required. Full descriptive name of the shade.'])
      ws.add_row(['brand          — Optional but recommended. Must match an existing brand name exactly (case-insensitive).'])
      ws.add_row(['product_family — Optional. Product line or family name. E.g. Apcolite Premium Gloss, Royale, Impressions.'])
      ws.add_row(['colour_family  — Optional. Used for grouping (Blues, Whites, Pastels, etc.).'])
      ws.add_row(['notes          — Optional. Any special notes for store staff.'])
      ws.add_row(['active         — Optional. Accepts: true, false, yes, no, 1, 0. Defaults to true.'])
      ws.add_row([''])
      ws.add_row(['Import Notes:'])
      ws.add_row(['- Rows 1, 2, 3 in this template are headers/descriptors — they are skipped automatically.'])
      ws.add_row(['- Matching is done by shade_code (case-insensitive). Existing shades are updated, new ones created.'])
      ws.add_row(['- The category is assigned during upload, not in the file. All shades in a single file belong to one category.'])
      ws.add_row(['- Backwards compatible: files with a "manufacturer" column header are also accepted.'])
      ws.column_widths 90
    end

    send_data(package.to_stream.read,
      filename:     'shade_catalogue_template.xlsx',
      type:         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition:  'attachment')
  end

  # GET /setup/shade_catalogues/export
  def export
    @shades = ShadeCatalogue.includes(:product_category).ordered

    package = Axlsx::Package.new
    wb = package.workbook

    hdr     = wb.styles.add_style bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11
    even    = wb.styles.add_style bg_color: 'F1F5F9', fg_color: '334155', sz: 10
    odd     = wb.styles.add_style bg_color: 'FFFFFF', fg_color: '334155', sz: 10

    wb.add_worksheet(name: 'Shade Catalogue') do |ws|
      ws.add_row(
        ['Category', 'Shade Code', 'Shade Name', 'Brand', 'Product Family', 'Colour Family', 'Notes', 'Active'],
        style: hdr
      )

      @shades.each_with_index do |s, i|
        row_style = i.even? ? even : odd
        ws.add_row([
          s.product_category&.name,
          s.shade_code,
          s.shade_name,
          s.brand&.name,
          s.product_family,
          s.colour_family,
          s.notes,
          s.active
        ], style: row_style)
      end

      ws.column_widths 20, 14, 24, 18, 26, 16, 30, 8
    end

    send_data(package.to_stream.read,
      filename:    "shade_catalogue_#{Date.today.strftime('%Y%m%d')}.xlsx",
      type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition: 'attachment')
  end

  # ─── Import actions ──────────────────────────────────────────

  # GET /setup/shade_catalogues/import
  def import_index
    @imports = ShadeCatalogueImport.recent.limit(50)
  end

  # GET /setup/shade_catalogues/import_new
  def import_new
    @paint_categories = ProductCategory.paint_types.active.ordered
  end

  # POST /setup/shade_catalogues/import_create
  def import_create
    file        = params[:file]
    category_id = params[:product_category_id]

    unless file.present? && file.content_type.in?(valid_import_mime_types)
      redirect_to import_new_setup_shade_catalogues_path, alert: 'Please upload a valid .xlsx file.'
      return
    end

    category = ProductCategory.find_by(id: category_id)
    unless category&.is_paint_type?
      redirect_to import_new_setup_shade_catalogues_path, alert: 'Please select a valid paint category.'
      return
    end

    import = ShadeCatalogueImport.create!(
      organisation:     current_user.organisation,
      user:             current_user,
      product_category: category,
      file_name:        file.original_filename,
      file_size:        file.size,
      status:           'pending',
      file_data:        Base64.encode64(file.read)
    )

    ShadeCatalogueImportJob.perform_later(import.id)

    redirect_to import_setup_shade_catalogues_path,
      notice: "Import started — #{file.original_filename} is being processed in the background."
  end

  # GET /setup/shade_catalogues/imports/:id
  def import_show
    @import = ShadeCatalogueImport.find(params[:id])
  end

  # GET /setup/shade_catalogues/imports/:id/download_errors
  def import_download_errors
    @import = ShadeCatalogueImport.find(params[:id])

    unless @import.has_errors?
      redirect_to import_show_setup_shade_catalogue_path(@import),
        alert: 'No errors to download.'
      return
    end

    send_data generate_import_error_report(@import),
      filename:    "shade_import_errors_#{@import.id}_#{Date.today}.xlsx",
      type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition: 'attachment'
  end

  private

  def set_shade
    @shade = ShadeCatalogue.find(params[:id])
  end

  def shade_params
    params.require(:shade_catalogue).permit(
      :product_category_id, :shade_code, :shade_name,
      :brand_id, :product_family, :colour_family, :notes, :active
    )
  end

  def valid_import_mime_types
    [
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-excel',
      'application/octet-stream'
    ]
  end

  def generate_import_error_report(import)
    package = Axlsx::Package.new
    wb      = package.workbook

    wb.add_worksheet(name: 'Import Errors') do |sheet|
      headers = %w[row_number error shade_code shade_name brand product_family colour_family notes active]
      sheet.add_row headers
      import.error_rows.each do |row|
        sheet.add_row headers.map { |h| row[h].to_s }
      end
    end

    package.to_stream.read
  end

end

