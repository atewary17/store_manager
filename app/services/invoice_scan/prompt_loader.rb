module InvoiceScan
  class PromptLoader
    DIR = Rails.root.join('config/prompts/invoice_scan')

    # Returns the prompt text for a given supplier name.
    # "Asian Paints Limited" → slug "asian_paints_limited"
    #   → tries asian_paints_limited.txt
    #   → falls back to 2-word prefix: asian_paints*.txt
    #   → falls back to generic.txt
    def self.for_supplier(supplier_name)
      slug = supplier_name.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/_+$/, '').gsub(/^_+/, '')
      path = DIR.join("#{slug}.txt")

      unless path.exist?
        prefix    = slug.split('_').first(2).join('_')
        candidate = DIR.glob("#{prefix}*.txt").reject { |p| p.basename.to_s == 'generic.txt' }.first
        path      = candidate if candidate
      end

      path = DIR.join('generic.txt') unless path&.exist?
      File.read(path)
    end
  end
end
