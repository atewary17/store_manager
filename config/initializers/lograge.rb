# config/initializers/lograge.rb
#
# Lograge condenses each request's noisy multi-line log into ONE key=value line,
# so a failing request (and its exception) stands out instead of drowning in SQL
# and partial-render noise.
#
# NOTE: lograge only covers HTTP requests. Background-job (GoodJob) errors are NOT
# captured here — those still log via GoodJob's on_thread_error hook + the
# /good_job dashboard, and are the job for a dedicated error tracker (Phase 2).
Rails.application.configure do
  # Enabled in production (clean prod logs) and development (the whole point —
  # spotting errors). Flip the development half to false if you prefer Rails'
  # default verbose dev logging.
  config.lograge.enabled = Rails.env.production? || Rails.env.development?

  # Readable key=value output, e.g.
  #   method=GET path=/purchasing/digitise/12 status=500 duration=42.1 error=...
  config.lograge.formatter = Lograge::Formatters::KeyValue.new

  config.lograge.custom_options = lambda do |event|
    opts = {}

    # Surface the exception prominently — this is the reason for adding lograge.
    if (ex = event.payload[:exception_object])
      opts[:error]       = "#{ex.class}: #{ex.message}"
      opts[:error_first] = ex.backtrace&.first
    end

    # Request params only in development — avoids leaking PII / secrets / large
    # AI payloads (GSTINs, supplier data, parsed invoice JSON) into prod logs.
    if Rails.env.development?
      params = event.payload[:params]
      opts[:params] = params.except('controller', 'action', 'format', 'authenticity_token') if params
    end

    opts
  end
end
