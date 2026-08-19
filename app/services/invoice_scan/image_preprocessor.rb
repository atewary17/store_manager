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

        # Downscale-only cap. Groq counts image tokens by resolution, and the free
        # tier allows only 8,000 tokens/min — so the image must stay small enough to
        # fit (with the prompt) under that. We do NOT upscale: extra pixels add tokens
        # without adding real detail. The `>` flag only shrinks images larger than the
        # cap, so already-small scans keep their native resolution. Tune the cap with
        # GROQ_IMAGE_MAX_EDGE if you move to a higher (paid) tier and want more detail.
        max_edge = (ENV["GROQ_IMAGE_MAX_EDGE"].presence || 500).to_i

        image = MiniMagick::Image.open(tmp.path)
        image.combine_options do |c|
          c.resize "#{max_edge}x#{max_edge}>"  # shrink to fit the token budget (never upscale)
          # NOTE: no unsharp/normalize — qwen3.6 uses content-adaptive tiling, and the
          # extra high-frequency detail those add inflates the image-token count past
          # the 8k free-tier budget. Plain downscale keeps it lean.
          c.quality '82'
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
