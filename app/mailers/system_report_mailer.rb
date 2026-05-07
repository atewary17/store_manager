class SystemReportMailer < ApplicationMailer
  RECIPIENTS = %w[atewary17@gmail.com subhasishr7@gmail.com].freeze

  def daily_report(date = Date.today)
    @date       = date
    @date_label = date.strftime('%d %b %Y')
    day_range   = date.beginning_of_day..date.end_of_day
    month_range = 30.days.ago.beginning_of_day..Time.current

    # ── Jobs for the day ─────────────────────────────────────────
    day_jobs        = GoodJob::Job.where(created_at: day_range)
    @jobs_queued    = day_jobs.where(finished_at: nil, performed_at: nil).count
    @jobs_running   = day_jobs.where.not(performed_at: nil).where(finished_at: nil).count
    @jobs_succeeded = day_jobs.where.not(finished_at: nil).where(error: nil).count
    @jobs_errored   = day_jobs.where.not(error: nil).where.not(finished_at: nil).count
    @jobs_discarded = day_jobs.where(error_event: 5).count
    @jobs_total     = day_jobs.count

    # ── API calls for the day ─────────────────────────────────────
    day_api          = ExternalApiLog.where(created_at: day_range)
    @api_total       = day_api.count
    @api_succeeded   = day_api.succeeded.count
    @api_errored     = day_api.failed.count
    @api_avg_ms      = day_api.where.not(duration_ms: nil).average(:duration_ms)&.round(1) || 0
    @api_success_pct = @api_total > 0 ? (@api_succeeded.to_f / @api_total * 100).round(1) : 0

    # ── Monthly averages (last 30 days) ───────────────────────────
    month_jobs       = GoodJob::Job.where(created_at: month_range)
    month_api        = ExternalApiLog.where(created_at: month_range)
    month_api_ok     = month_api.succeeded.count
    @monthly = {
      jobs_per_day:  (month_jobs.count.to_f / 30).round(1),
      api_per_day:   (month_api.count.to_f / 30).round(1),
      success_rate:  month_api.count > 0 ? (month_api_ok.to_f / month_api.count * 100).round(1) : 0,
      avg_ms:        month_api.where.not(duration_ms: nil).average(:duration_ms)&.round(1) || 0
    }

    # ── By organisation ───────────────────────────────────────────
    @org_stats = ExternalApiLog
                   .where(created_at: day_range)
                   .joins(:organisation)
                   .group('organisations.name')
                   .select("organisations.name AS org_name,
                            COUNT(*) AS total,
                            SUM(CASE WHEN external_api_logs.status = 'success' THEN 1 ELSE 0 END) AS succeeded,
                            SUM(CASE WHEN external_api_logs.status = 'error'   THEN 1 ELSE 0 END) AS errored")
                   .order('total DESC')
                   .to_a

    # ── By service/operation ──────────────────────────────────────
    @service_stats = ExternalApiLog
                       .where(created_at: day_range)
                       .group(:service, :operation)
                       .select("service, operation,
                                COUNT(*) AS total,
                                SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS succeeded,
                                AVG(duration_ms) AS avg_ms")
                       .order('total DESC')
                       .to_a

    # ── Job class breakdown ───────────────────────────────────────
    @job_class_stats = GoodJob::Job
                         .where(created_at: day_range)
                         .group(:job_class)
                         .select("job_class,
                                  COUNT(*) AS total,
                                  SUM(CASE WHEN finished_at IS NOT NULL AND error IS NULL THEN 1 ELSE 0 END) AS succeeded,
                                  SUM(CASE WHEN error IS NOT NULL THEN 1 ELSE 0 END) AS errored")
                         .order('total DESC')
                         .to_a rescue []

    mail(
      to:      RECIPIENTS,
      subject: "System Report — #{@date_label}"
    )
  end
end
