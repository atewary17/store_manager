# app/helpers/application_helper.rb
module ApplicationHelper

  BRAND_HEX_MAP = {
    'asian paints' => '#e31837',
    'berger'       => '#0057a8',
    'birla opus'   => '#6d2b8f',
    'salimar'      => '#f47920',
  }.freeze

  # Returns a hex colour string for a brand, falling back to accent colour
  def brand_hex(brand)
    key = brand.name.to_s.downcase
    BRAND_HEX_MAP.each { |k, v| return v if key.include?(k) }
    '#4f8ef7'
  end
  def status_badge_class(status)
    case status.to_s
    when 'done'       then 'badge-active'
    when 'processing' then 'badge-plan'
    when 'pending'    then 'badge-inactive'
    when 'failed'     then 'badge-inactive'
    else 'badge-inactive'
    end
  end
end