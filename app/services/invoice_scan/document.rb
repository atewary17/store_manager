module InvoiceScan
  # Turns an uploaded file into a list of single-page images.
  #
  # This is deliberately provider-agnostic: page splitting is a property of the
  # document, not of whichever AI reads it. Keeping it here is what lets a new
  # engine support multi-page PDFs without reimplementing anything.
  #
  #   doc = Document.new(base64_data: b64, mime_type: 'application/pdf')
  #   doc.pages          # => [[b64, 'image/jpeg'], [b64, 'image/jpeg'], ...]
  #   doc.preview_image  # => b64 of page 1, or nil for single images
  #
  class Document
    PDF_MIME = 'application/pdf'.freeze
    PDF_DPI  = '300'.freeze

    def initialize(base64_data:, mime_type:)
      @base64_data = base64_data
      @mime_type   = mime_type
    end

    def pdf?
      @mime_type == PDF_MIME
    end

    def pages
      @pages ||= pdf? ? pdf_to_jpegs : [[@base64_data, @mime_type]]
    end

    def preview_image
      pdf? ? pages.first&.first : nil
    end

    private

    def pdf_to_jpegs
      bin = `which pdftoppm`.strip
      if bin.empty?
        raise 'pdftoppm not found. Install: brew install poppler (Mac) / apt install poppler-utils (Linux)'
      end

      tmp_pdf = Tempfile.new(['invoice', '.pdf'])
      tmp_dir = Dir.mktmpdir('invoice_pages')

      begin
        tmp_pdf.binmode
        tmp_pdf.write(Base64.decode64(@base64_data))
        tmp_pdf.flush

        system(bin, '-jpeg', '-r', PDF_DPI, tmp_pdf.path, File.join(tmp_dir, 'page'))

        paths = Dir.glob("#{tmp_dir}/*.jpg").sort
        raise 'PDF conversion produced no pages — is this a valid PDF?' if paths.empty?

        paths.map { |p| [Base64.strict_encode64(File.binread(p)), 'image/jpeg'] }
      ensure
        tmp_pdf.close
        tmp_pdf.unlink
        FileUtils.rm_rf(tmp_dir)
      end
    end
  end
end
