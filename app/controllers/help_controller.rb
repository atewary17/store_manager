# app/controllers/help_controller.rb
#
# Lazy-loaded help content for the slide-over drawer.
# GET /help?key=purchasing/digitise/show&locale=bn  ->  rendered HTML fragment
class HelpController < ApplicationController
  def show
    key    = sanitize_key(params[:key])
    locale = resolve_locale(params[:locale])
    html   = HelpContent.render(key, locale)

    render html: html, layout: false
  end

  private

  # Allow only lowercase letters, digits, underscore and slash — and never
  # let "." (path traversal) through. Collapses stray slashes.
  def sanitize_key(raw)
    k = raw.to_s.downcase.gsub(/[^a-z0-9_\/]/, '')
    k = k.squeeze('/').gsub(/\A\/|\/\z/, '')
    k.presence || '_fallback'
  end

  # Clamp the requested locale to the languages THIS org has enabled (English
  # always; extras set by a System Admin on the Organisation settings page).
  # Defense in depth — a hand-crafted ?locale=bn on a non-Bengali org still
  # returns English. The content loader also falls back to English when a file
  # is missing.
  def resolve_locale(raw)
    l       = raw.to_s.downcase
    allowed = current_user&.organisation&.help_locales.presence || %w[en]
    allowed.include?(l) ? l.to_sym : :en
  end
end
