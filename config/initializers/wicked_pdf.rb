# config/initializers/wicked_pdf.rb

# Guard: wicked_pdf may not be loaded if not in Gemfile
return unless defined?(WickedPdf)

WickedPdf.config do |c|
  # Try the wkhtmltopdf-binary gem first, then common system paths
  binary =
    begin
      require 'wkhtmltopdf-binary'
      WkhtmltopdfBinary.location
    rescue LoadError, NameError
      [
        '/usr/local/bin/wkhtmltopdf',    # Homebrew Intel
        '/opt/homebrew/bin/wkhtmltopdf', # Homebrew Apple Silicon
        '/usr/bin/wkhtmltopdf',          # Linux
        `which wkhtmltopdf 2>/dev/null`.strip
      ].find { |p| p.present? && File.executable?(p.to_s) }
    end

  c.wkhtmltopdf = binary if binary.present?
  c.page_size   = 'A4'
  c.encoding    = 'UTF-8'
end