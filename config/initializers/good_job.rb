# config/initializers/good_job.rb
Rails.application.configure do
  config.good_job.preserve_job_records = true
  config.good_job.retry_on_unhandled_error = false
  config.good_job.on_thread_error = ->(exception) { Rails.logger.error(exception) }
  # :async  — jobs run inside the Puma process. The default, and what
  #           single-process hosts like Render use.
  # :external — jobs run only in a dedicated `good_job start` process. Use where
  #           a separate worker exists, so an invoice scan (which peaks around
  #           513MB in ImageMagick) cannot stall page loads.
  config.good_job.execution_mode =
    ENV.fetch('GOOD_JOB_EXECUTION_MODE', 'async').to_sym
  config.good_job.max_threads = ENV.fetch('GOOD_JOB_MAX_THREADS', 3).to_i
  config.good_job.queues = 'default,enrichment,low_priority'
  config.good_job.enable_cron = true
  config.good_job.cron_entries_source = :file   # reads config/recurring.yml
end