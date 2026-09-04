module HelpHelper
  # Stable help key for the current screen, derived from the route.
  # e.g. PurchasingController::DigitiseController#show -> "purchasing/digitise/show"
  # Dynamic :id pages collapse to one key (all invoice reviews share one doc).
  def help_page_key
    "#{controller_path}/#{action_name}"
  end
end
