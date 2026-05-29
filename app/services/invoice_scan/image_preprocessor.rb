module InvoiceScan
  # Enhances invoice images before sending to the AI:
  #   - 2× upscale (bicubic) so narrow column gaps get more pixels
  #   - Unsharp mask to crisp up character edges
  #   - Normalize contrast so dark ink on light paper is distinct
  #
  # Returns the same base64/mime pair, enhanced.
  # Falls back to the original silently if MiniMagick is unavailable or fails.
  class ImagePreprocessor
    def self.call(base64_data:, mime_type:)
      new(base64_data: base64_data, mime_type: mime_type).call
    end

    def initialize(base64_data:, mime_type:)
      @base64_data = base64_data
      @mime_type   = mime_type
    end

    def call
      require 'mini_magick'

      ext = ext_for(@mime_type)
      tmp = Tempfile.new(['invoice_pre', ext])
      out = Tempfile.new(['invoice_post', '.jpg'])

      begin
        tmp.binmode
        tmp.write(Base64.decode64(@base64_data))
        tmp.flush

        image = MiniMagick::Image.open(tmp.path)
        image.combine_options do |c|
          c.resize '200%'               # 2× upscale — bicubic by default
          c.resize '5700x5700>'         # cap to ≤32.49M px (Groq hard limit: 33.18M)
          c.unsharp '0x1+1.5+0.02'      # sharpen edges
          c.normalize                   # stretch contrast to full range
          c.quality '92'
        end
        image.format 'jpeg'
        image.write out.path

        [Base64.strict_encode64(File.binread(out.path)), 'image/jpeg']
      ensure
        tmp.close; tmp.unlink
        out.close; out.unlink
      end

    rescue => e
      Rails.logger.warn "[ImagePreprocessor] Failed (#{e.class}: #{e.message}) — using original"
      [@base64_data, @mime_type]
    end

    private

    def ext_for(mime)
      case mime
      when 'image/png'  then '.png'
      when 'image/webp' then '.webp'
      else '.jpg'
      end
    end
  end
end
