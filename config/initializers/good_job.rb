# config/initializers/good_job.rb
Rails.application.configure do
  config.good_job.preserve_job_records = true
  config.good_job.retry_on_unhandled_error = false
  config.good_job.on_thread_error = ->(exception) { Rails.logger.error(exception) }
  config.good_job.execution_mode = :async   # runs in same process (fine for Render)
  config.good_job.max_threads = 3
  config.good_job.queues = 'default,enrichment'
  config.good_job.enable_cron = true
  config.good_job.cron_entries_source = :file   # reads config/recurring.yml
end