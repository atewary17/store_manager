module InvoiceScan
  # Vision-OCR pipeline: Google Vision OCR → Groq text parse → Validator
  # Each step is logged separately to ExternalApiLog.
  # Falls back to InvoiceAiService (direct vision) when GOOGLE_VISION_API_KEY is absent.
  class Pipeline
    KNOWN_SUPPLIERS = {
      'asian paints'  => 'Asian Paints Limited',
      'shalimar'      => 'Shalimar Paints Limited',
      'berger'        => 'Berger Paints India Limited',
      'nerolac'       => 'Kansai Nerolac Paints Limited',
      'dulux'         => 'AkzoNobel India Limited',
      'duke paints'   => 'Duke Paints',
    }.freeze

    def self.call(base64_data:, mime_type:, supplier_hint: nil, organisation_id: nil, user_id: nil)
      new(
        base64_data:     base64_data,
        mime_type:       mime_type,
        supplier_hint:   supplier_hint,
        organisation_id: organisation_id,
        user_id:         user_id
      ).call
    end

    def initialize(base64_data:, mime_type:, supplier_hint: nil, organisation_id: nil, user_id: nil)
      @base64_data     = base64_data
      @mime_type       = mime_type
      @supplier_hint   = supplier_hint
      @organisation_id = organisation_id
      @user_id         = user_id
    end

    def call
      pages, preview_image = prepare_pages

      ocr_pages    = []
      page_results = []

      total_pages = pages.size
      Rails.logger.info "╔══════════════════════════════════════════════════════════════╗"
      Rails.logger.info "║  InvoiceScan::Pipeline  START  (#{total_pages} page#{'s' if total_pages != 1})#{' ' * [30 - total_pages.to_s.length, 0].max}║"
      Rails.logger.info "╚══════════════════════════════════════════════════════════════╝"

      pages.each_with_index do |(page_b64, _page_mime), idx|
        page_num = idx + 1

        Rails.logger.info "┌──────────────────────────────────────────────────────────────┐"
        Rails.logger.info "│  STEP 2 — OCR  (Google Vision)  ·  Page #{page_num}/#{total_pages}#{' ' * [20 - "#{page_num}/#{total_pages}".length, 0].max}│"
        Rails.logger.info "└──────────────────────────────────────────────────────────────┘"

        ocr = run_ocr(page_b64, page_num)

        if ocr[:success]
          Rails.logger.info "  ✓ OCR complete — #{ocr[:text].to_s.length} chars extracted"
        else
          Rails.logger.info "  ✗ OCR FAILED  — #{ocr[:error]}"
        end

        ocr_pages << {
          'page'        => page_num,
          'text'        => ocr[:text].to_s,
          'char_count'  => ocr[:text].to_s.length,
          'ocr_success' => ocr[:success],
          'ocr_error'   => ocr[:error]
        }

        # Auto-detect supplier from first page OCR text if not already known
        @supplier_hint ||= detect_supplier(ocr[:text].to_s) if page_num == 1

        Rails.logger.info "┌──────────────────────────────────────────────────────────────┐"
        Rails.logger.info "│  STEP 3 — AI Parse  (Groq)  ·  Page #{page_num}/#{total_pages}  ·  supplier: #{@supplier_hint.to_s.truncate(15)}"
        Rails.logger.info "└──────────────────────────────────────────────────────────────┘"

        parse = run_ai_parse(ocr[:text].to_s, page_num)

        if parse[:success]
          item_count = parse.dig(:data, 'items')&.size || 0
          Rails.logger.info "  ✓ AI parse complete — #{item_count} line items extracted"
        else
          Rails.logger.info "  ✗ AI parse FAILED  — #{parse[:error]}"
        end

        page_results << parse.merge(page_num: page_num)
      end

      Rails.logger.info "┌──────────────────────────────────────────────────────────────┐"
      Rails.logger.info "│  STEP 4 — Validate + Merge                                   │"
      Rails.logger.info "└──────────────────────────────────────────────────────────────┘"

      merged = merge_results(page_results, ocr_pages)

      flag_count = merged.dig(:data, '_meta', 'validation_flags')&.size || 0
      Rails.logger.info "  ✓ Merge complete — #{flag_count} validation flag#{'s' if flag_count != 1}"
      Rails.logger.info "╔══════════════════════════════════════════════════════════════╗"
      Rails.logger.info "║  InvoiceScan::Pipeline  END  — #{merged[:success] ? 'SUCCESS' : 'FAILED '}#{' ' * 28}║"
      Rails.logger.info "╚══════════════════════════════════════════════════════════════╝"

      merged.merge(preview_image: preview_image, provider: 'groq')

    rescue => e
      { success: false, error: e.message, data: nil, raw_response: nil,
        preview_image: nil, provider: 'groq' }
    end

    private

    # ── Page preparation ──────────────────────────────────────────────────────

    def prepare_pages
      if @mime_type == 'application/pdf'
        pages   = pdf_to_jpegs
        preview = pages.first&.first
        [pages, preview]
      else
        [[ [@base64_data, @mime_type] ], nil]
      end
    end

    def pdf_to_jpegs
      bin = `which pdftoppm`.strip
      raise 'pdftoppm not found. Install: brew install poppler (Mac) / apt install poppler-utils' if bin.empty?

      tmp_pdf = Tempfile.new(['invoice', '.pdf'])
      tmp_dir = Dir.mktmpdir('invoice_pages')
      begin
        tmp_pdf.binmode
        tmp_pdf.write(Base64.decode64(@base64_data))
        tmp_pdf.flush
        system(bin, '-jpeg', '-r', '300', tmp_pdf.path, File.join(tmp_dir, 'page'))
        pages = Dir.glob("#{tmp_dir}/*.jpg").sort
        raise 'PDF conversion produced no pages' if pages.empty?
        pages.map { |p| [Base64.strict_encode64(File.binread(p)), 'image/jpeg'] }
      ensure
        tmp_pdf.close; tmp_pdf.unlink; FileUtils.rm_rf(tmp_dir)
      end
    end

    # ── Pipeline steps ────────────────────────────────────────────────────────

    def run_ocr(base64, page_num)
      ExternalApiLog.record(
        service:         'google_vision',
        operation:       'invoice_ocr',
        organisation_id: @organisation_id,
        user_id:         @user_id,
        metadata:        { page: page_num, supplier_hint: @supplier_hint }
      ) do
        OcrClient.call(base64_data: base64)
      end
    end

    def run_ai_parse(ocr_text, page_num)
      ExternalApiLog.record(
        service:         'groq',
        operation:       'invoice_parse',
        organisation_id: @organisation_id,
        user_id:         @user_id,
        metadata:        { page: page_num, supplier_hint: @supplier_hint,
                           ocr_chars: ocr_text.length, pipeline: 'vision_ocr' }
      ) do
        AiParser.call(ocr_text: ocr_text, supplier_hint: @supplier_hint, page_num: page_num)
      end
    end

    def detect_supplier(ocr_text)
      lower = ocr_text.downcase
      KNOWN_SUPPLIERS.each { |kw, name| return name if lower.include?(kw) }
      nil
    end

    # ── Result merging ────────────────────────────────────────────────────────

    def merge_results(results, ocr_pages)
      successful = results.select { |r| r[:success] && r[:data].present? }

      if successful.empty?
        return {
          success:      false,
          error:        results.map { |r| r[:error] }.compact.join(' | '),
          data:         nil,
          raw_response: results.first&.dig(:raw_response)
        }
      end

      base      = successful.first[:data]
      all_items = successful.flat_map { |r| r[:data]['items'] || [] }

      # Resolve unit_rate: prefer whichever of unit_rate / rate_per_pack satisfies qty × rate = value
      all_items.each do |item|
        qty = item['quantity'].to_f
        val = item['value'].to_f
        rpp = item['rate_per_pack'].to_f
        ur  = item['unit_rate'].to_f
        next unless qty > 0 && val > 0

        tol = [val * 0.005, 1.0].max
        if rpp > 0 && (qty * rpp - val).abs <= tol
          item['unit_rate'] = rpp
        elsif !(ur > 0 && (qty * ur - val).abs <= tol) && rpp > 0
          item['unit_rate'] = rpp
        end
      end

      validation     = Validator.call(all_items)
      ai_total_pages = successful.map { |r| r[:data].dig('header', 'total_pages').to_i }.max
      pages_scanned  = successful.size

      # Compute top-level step statuses for display in the index
      ocr_ok    = ocr_pages.count { |p| p['ocr_success'] }
      ocr_fail  = ocr_pages.count { |p| p['ocr_success'] == false }
      ocr_status = if ocr_pages.empty?    then 'n/a'
                   elsif ocr_fail == 0    then 'success'
                   elsif ocr_ok  == 0     then 'failed'
                   else                        'partial'
                   end

      ai_ok   = results.count { |r| r[:success] && r[:data].present? }
      ai_fail = results.count { |r| !r[:success] }
      ai_status = if ai_fail == 0          then 'success'
                  elsif ai_ok  == 0        then 'failed'
                  else                          'partial'
                  end

      merged_data = base.merge(
        'items' => validation[:items],
        '_meta' => {
          'pages_scanned'    => pages_scanned,
          'page_count'       => [ai_total_pages, pages_scanned].max,
          'pipeline'         => 'vision_ocr',
          'supplier_hint'    => @supplier_hint,
          'ocr_status'       => ocr_status,
          'ai_status'        => ai_status,
          'validation_flags' => validation[:flags],
          'validation_valid' => validation[:valid],
          'ocr_pages'        => ocr_pages,
          'pages_data'       => successful.map { |r|
            {
              'page_num'    => r[:page_num],
              'item_count'  => (r[:data]['items'] || []).size,
              'page_number' => r[:data].dig('header', 'page_number'),
              'total_pages' => r[:data].dig('header', 'total_pages')
            }
          }
        }
      )

      {
        success:      true,
        data:         merged_data,
        raw_response: successful.map { |r| r[:raw_response] }.join("\n---page---\n"),
        error:        nil
      }
    end
  end
end
