# app/services/help_content.rb
#
# Loads a help-manual Markdown file for a given page-key + locale, renders it to
# safe HTML. Used by HelpController (lazy-fetched by the help drawer).
#
# Lookup chain:  app/help/<locale>/<key>.md  →  app/help/en/<key>.md  →  app/help/en/_fallback.md
class HelpContent
  ROOT = Rails.root.join('app', 'help').freeze

  ALLOWED_TAGS = %w[
    h1 h2 h3 h4 h5 h6 p ul ol li strong em b i code pre blockquote
    a hr br table thead tbody tr th td span div img figure figcaption
  ].freeze
  # img + src/alt/width/height so help screenshots and GIFs can be embedded:
  #   ![Select supplier](/help_media/digitise/new-step1.gif)
  ALLOWED_ATTRS = %w[href title class src alt width height].freeze

  # Returns sanitized HTML for the key+locale (never raises — always returns something).
  def self.render(key, locale)
    md   = read(key, locale)
    html = Kramdown::Document.new(md).to_html
    ActionController::Base.helpers.sanitize(html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRS)
  rescue => e
    Rails.logger.warn("[HelpContent] render failed for #{key}/#{locale}: #{e.message}")
    '<p>Help is unavailable right now.</p>'.html_safe
  end

  # Raw Markdown string for the key+locale, with fallbacks.
  def self.read(key, locale)
    path = safe_path(key, locale) || safe_path(key, :en) || safe_path('_fallback', :en)
    path ? File.read(path) : "## Help coming soon\n\nThere's no guide for this page yet."
  end

  # Resolve <locale>/<key>.md only if it stays inside app/help (no traversal).
  def self.safe_path(key, locale)
    candidate = ROOT.join(locale.to_s, "#{key}.md").expand_path
    return nil unless candidate.to_s.start_with?(ROOT.to_s + File::SEPARATOR)
    return nil unless File.file?(candidate)
    candidate
  end
  private_class_method :safe_path
end
