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

  # Whitelisted directly (not via I18n.available_locales) so a not-yet-restarted
  # server or i18n config quirk can't silently swallow a valid language. The
  # content loader still falls back to English when a file is missing.
  SUPPORTED_LOCALES = %w[en bn hi].freeze

  def resolve_locale(raw)
    l = raw.to_s.downcase
    SUPPORTED_LOCALES.include?(l) ? l.to_sym : :en
  end
end
