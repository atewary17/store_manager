# app/services/help_content.rb
#
# Loads a help-manual Markdown file for a given page-key + locale, renders it to
# safe HTML. Used by HelpController (lazy-fetched by the help drawer).
#
# LOOKUP CHAIN
#
# Candidate keys are built once (most specific first), then each is tried in the
# requested locale before falling back to English. For
# "purchasing/purchase_invoices/edit":
#
#   purchasing/purchase_invoices/edit      the page's own doc
#   purchasing/purchase_invoices/new       edit and new render the same form, so
#                                          one doc serves both (see ACTION_ALIASES)
#   purchasing/purchase_invoices/_fallback resource-level guidance
#   purchasing/_fallback                   section-level guidance
#   _fallback                              global
#
# The section levels are what let a handful of docs cover every page in a
# section — a page with no doc of its own still gets something relevant rather
# than "Help coming soon".
class HelpContent
  ROOT = Rails.root.join('app', 'help').freeze

  # Actions that render the same screen as another action. Checked only when the
  # action has no doc of its own, so a dedicated edit.md always wins.
  ACTION_ALIASES = { 'edit' => 'new' }.freeze

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

  # Raw Markdown string for the key+locale, walking the chain described above.
  def self.read(key, locale)
    path = candidate_keys(key).lazy.filter_map { |k|
      safe_path(k, locale) || safe_path(k, :en)
    }.first

    path ? File.read(path) : "## Help coming soon\n\nThere's no guide for this page yet."
  end

  # Ordered, most specific first. Always ends with the global '_fallback'.
  #
  #   "purchasing/purchase_invoices/edit" =>
  #     ["purchasing/purchase_invoices/edit",
  #      "purchasing/purchase_invoices/new",
  #      "purchasing/purchase_invoices/_fallback",
  #      "purchasing/_fallback",
  #      "_fallback"]
  def self.candidate_keys(key)
    parts  = key.to_s.split('/').reject(&:blank?)
    return ['_fallback'] if parts.empty?

    keys   = [parts.join('/')]
    action = parts.last

    if (aliased = ACTION_ALIASES[action]) && parts.size > 1
      keys << (parts[0..-2] + [aliased]).join('/')
    end

    # Walk up: drop the action, then each namespace segment, adding a _fallback
    # at every level. "a/b/c" gives "a/b/_fallback", then "a/_fallback".
    parts[0..-2].size.downto(1) do |n|
      keys << (parts.first(n) + ['_fallback']).join('/')
    end

    keys << '_fallback'
    keys.uniq
  end
  private_class_method :candidate_keys

  # Resolve <locale>/<key>.md only if it stays inside app/help (no traversal).
  def self.safe_path(key, locale)
    candidate = ROOT.join(locale.to_s, "#{key}.md").expand_path
    return nil unless candidate.to_s.start_with?(ROOT.to_s + File::SEPARATOR)
    return nil unless File.file?(candidate)
    candidate
  end
  private_class_method :safe_path
end
