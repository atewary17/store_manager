ActionMailer::Base.delivery_method      = :smtp
ActionMailer::Base.raise_delivery_errors = true
ActionMailer::Base.smtp_settings = {
  address:              'smtp-relay.brevo.com',
  port:                 587,
  authentication:       :login,
  user_name:            ENV['BREVO_SMTP_LOGIN'],
  password:             ENV['BREVO_SMTP_PASSWORD'],
  enable_starttls_auto: true
}

Rails.application.config.action_mailer.default_url_options = {
  host: ENV.fetch('APP_HOST', 'localhost:3000')
}
