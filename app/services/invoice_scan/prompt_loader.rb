module InvoiceScan
  class PromptLoader
    DIR = Rails.root.join('config/prompts/invoice_scan')

    # Returns the prompt text for a given supplier name.
    # Converts supplier name to a filesystem slug (e.g. "Asian Paints Limited" → "asian_paints_limited"),
    # falls back to generic.txt if no supplier-specific file exists.
    def self.for_supplier(supplier_name)
      slug = supplier_name.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/_+$/, '').gsub(/^_+/, '')
      path = DIR.join("#{slug}.txt")

      # Try exact slug first, then prefix match for common variations
      # e.g. "asian_paints_limited" should match "asian_paints.txt"
      unless path.exist?
        prefix = slug.split('_').first(2).join('_')
        candidate = DIR.glob("#{prefix}*.txt").reject { |p| p.basename.to_s == 'generic.txt' }.first
        path = candidate if candidate
      end

      path = DIR.join('generic.txt') unless path&.exist?
      File.read(path)
    end
  end
end
