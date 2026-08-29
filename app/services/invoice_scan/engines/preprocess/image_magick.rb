module InvoiceScan
  module Engines
    module Preprocess
      # PAGE -> PAGE
      #
      # Thin adapter over the existing InvoiceScan::ImagePreprocessor so image
      # enhancement becomes a swappable stage. The enhancement itself is
      # unchanged; ImagePreprocessor already falls back to the original image
      # if MiniMagick is unavailable.
      class ImageMagick < InvoiceScan::Engines::Base
        def self.role
          :preprocess
        end

        def call(page, _context)
          enhanced_b64, enhanced_mime = InvoiceScan::ImagePreprocessor.call(
            base64_data: page[:base64_data],
            mime_type:   page[:mime_type]
          )

          page.merge(base64_data: enhanced_b64, mime_type: enhanced_mime)
        end
      end
    end
  end
end
