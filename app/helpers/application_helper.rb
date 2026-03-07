# app/helpers/application_helper.rb
module ApplicationHelper
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