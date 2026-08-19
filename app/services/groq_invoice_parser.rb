# app/services/groq_invoice_parser.rb
#
# Sends purchase invoice pages to Groq (Llama 4 Scout vision) and returns a
# structured Ruby hash.
#
# PIPELINE PER PAGE:
#   1. ImageMagick preprocess  — 2× upscale, sharpen, normalize contrast
#   2. Groq vision call        — image + supplier-specific prompt → raw JSON
#   3. Deterministic validate  — math checks, field presence, type checks
#
# PDF FLOW  : all pages converted to JPEG via pdftoppm, one Groq call per page,
#             results merged — header + supplier from page 1, items from all pages.
# IMAGE FLOW: single image sent directly; supports JPG, PNG, WEBP.
#
require 'net/http'
require 'uri'
require 'base64'
require 'json'
require 'openssl'

class GroqInvoiceParser
  GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions'.freeze

  # Invoice scanning needs a VISION (multimodal) model — it sends the bill image.
  # Llama 4 Scout was decommissioned by Groq on 2026-07-17. Its replacement for
  # vision workloads is Qwen3.6 27B (multimodal; GPT-OSS 120B is text-only).
  # Override via GROQ_VISION_MODEL as the catalogue changes — see
  # https://console.groq.com/docs/models.
  # ⚠ qwen/qwen3.6-27b is currently a *preview* model on Groq and could be pulled
  #   at short notice; check the docs for the production-ready vision option.
  GROQ_MODEL = (ENV['GROQ_VISION_MODEL'].presence || 'qwen/qwen3.6-27b').freeze

  def self.call(base64_data:, mime_type:, supplier_hint: nil)
    new(base64_data: base64_data, mime_type: mime_type, supplier_hint: supplier_hint).call
  end

  def initialize(base64_data:, mime_type:, supplier_hint: nil)
    @base64_data   = base64_data
    @mime_type     = mime_type
    @supplier_hint = supplier_hint
    @api_key       = ENV['GROQ_API_KEY']
  end

  def call
    raise 'GROQ_API_KEY not set' unless @api_key.present?

    pages, preview_image = prepare_pages
    prompt               = InvoiceScan::PromptLoader.for_supplier(@supplier_hint)

    page_results = pages.each_with_index.map do |(page_b64, page_mime), idx|
      enhanced_b64, enhanced_mime = InvoiceScan::ImagePreprocessor.call(
        base64_data: page_b64,
        mime_type:   page_mime
      )
      parse_single_page(enhanced_b64, enhanced_mime, idx + 1, prompt)
    end

    merged = merge_page_results(page_results)
    merged.merge(preview_image: preview_image, provider: 'groq')

  rescue => e
    { success: false, error: e.message, data: nil, raw_response: nil,
      preview_image: nil, provider: 'groq' }
  end

  private

  # ── Page preparation ───────────────────────────────────────────────────────

  def prepare_pages
    if @mime_type == 'application/pdf'
      pages   = pdf_to_all_jpegs
      preview = pages.first&.first
      [pages, preview]
    else
      [[ [@base64_data, @mime_type] ], nil]
    end
  end

  def pdf_to_all_jpegs
    pdftoppm_bin = `which pdftoppm`.strip
    raise 'pdftoppm not found. Install: brew install poppler (Mac) / apt install poppler-utils (Linux)' if pdftoppm_bin.empty?

    tmp_pdf = Tempfile.new(['invoice', '.pdf'])
    tmp_dir = Dir.mktmpdir('invoice_pages')

    begin
      tmp_pdf.binmode
      tmp_pdf.write(Base64.decode64(@base64_data))
      tmp_pdf.flush

      system(pdftoppm_bin, '-jpeg', '-r', '300', tmp_pdf.path, File.join(tmp_dir, 'page'))

      pages = Dir.glob("#{tmp_dir}/*.jpg").sort
      raise 'PDF conversion produced no pages — is this a valid PDF?' if pages.empty?

      pages.map { |path| [Base64.strict_encode64(File.binread(path)), 'image/jpeg'] }
    ensure
      tmp_pdf.close; tmp_pdf.unlink; FileUtils.rm_rf(tmp_dir)
    end
  end

  # ── Single-page AI call ────────────────────────────────────────────────────

  def parse_single_page(base64, mime, page_num, prompt)
    body     = build_request_body(base64, mime, prompt)
    response = make_request(body)
    result   = parse_response(response)
    result.merge(page_num: page_num)
  rescue => e
    { success: false, error: "Page #{page_num}: #{e.message}", data: nil,
      raw_response: nil, page_num: page_num }
  end

  # ── Merge + validate results from all pages ────────────────────────────────

  def merge_page_results(results)
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

    # Merge header totals across ALL pages. On multi-page invoices the line items
    # are on page 1 but the GST/total summary is often on the LAST page. Without
    # this, page-1's zero totals would mask the real figures from page 2+.
    base['header'] = merge_headers(successful.map { |r| r[:data]['header'] }.compact)

    # Resolve unit_rate from rate_per_pack where needed
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

    validation = Suppliers::Registry.for(@supplier_hint).validator.call(all_items)

    ai_total_pages = successful.map { |r| r[:data].dig('header', 'total_pages').to_i }.max
    pages_scanned  = successful.size

    merged_data = base.merge(
      'items' => validation[:items],
      '_meta' => {
        'pages_scanned'    => pages_scanned,
        'page_count'       => [ai_total_pages, pages_scanned].max,
        'supplier_hint'    => @supplier_hint,
        'validation_flags' => validation[:flags],
        'validation_valid' => validation[:valid],
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

  # Combine headers from every page into one. Starts from page 1's header (which
  # carries supplier/invoice identity) and fills numeric total fields with the
  # largest non-zero value seen on any page — so summary figures on a later page
  # are not lost. Text fields take the first non-blank value across pages.
  def merge_headers(headers)
    return {} if headers.empty?
    merged = headers.first.dup

    numeric_totals = %w[
      total_cgst total_sgst total_igst total_amount total_taxable_amount
      cash_discount_amount cash_discount_percent
    ]
    numeric_totals.each do |field|
      best = headers.map { |h| h[field].to_f }.max
      merged[field] = best if best.to_f > merged[field].to_f
    end

    text_fields = %w[amount_in_words invoice_number invoice_date delivery_number
                     place_of_supply po_reference]
    text_fields.each do |field|
      next if merged[field].present?
      found = headers.map { |h| h[field] }.find(&:present?)
      merged[field] = found if found
    end

    merged
  end

  # ── HTTP helpers ───────────────────────────────────────────────────────────

  def build_request_body(image_base64, image_mime, prompt)
    {
      model:       GROQ_MODEL,
      temperature: 0.1,
      max_tokens:  8192,
      # Qwen3 is a reasoning model; without this it emits a <think>…</think> block
      # instead of clean JSON (and burns the token budget thinking). "none" makes it
      # answer directly. Harmless for non-reasoning models.
      reasoning_effort: 'none',
      messages: [
        {
          role:    'user',
          content: [
            { type: 'text', text: prompt },
            { type: 'image_url', image_url: { url: "data:#{image_mime};base64,#{image_base64}" } }
          ]
        }
      ]
    }
  end

  def make_request(body)
    uri  = URI.parse(GROQ_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.read_timeout = 120
    http.open_timeout = 10
    http.verify_mode  = OpenSSL::SSL::VERIFY_NONE

    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type']  = 'application/json'
    req['Authorization'] = "Bearer #{@api_key}"
    req.body = body.to_json

    http.request(req)
  end

  def parse_response(response)
    unless response.code.to_i == 200
      return {
        success:      false,
        error:        "Groq HTTP #{response.code}: #{response.body.to_s.truncate(300)}",
        data:         nil,
        raw_response: response.body
      }
    end

    outer = JSON.parse(response.body)
    text  = outer.dig('choices', 0, 'message', 'content').to_s.strip
    # Reasoning models (e.g. Qwen3) may prepend a <think>…</think> block — drop it.
    text  = text.sub(%r{\A\s*<think>.*?</think>\s*}mi, '').strip
    # Strip markdown code fences the model sometimes wraps JSON in.
    text  = text.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip
    data  =
      begin
        JSON.parse(text)
      rescue JSON::ParserError
        # Last resort: pull the outermost {…} object out of any surrounding prose.
        snippet = text[/\{.*\}/m]
        snippet ? JSON.parse(snippet) : raise
      end

    { success: true, data: data, raw_response: text, error: nil }

  rescue JSON::ParserError => e
    { success: false, error: "JSON parse failed: #{e.message}", data: nil, raw_response: text.to_s }
  end
end
