# app/controllers/status_controller.rb
# Inherits ActionController::Base directly — bypasses Devise completely.
class StatusController < ActionController::Base
  layout 'status'

  PIN = '713301'

  before_action :check_pin, only: [:index]

  def index
    now   = Time.current
    since = 24.hours.ago

    # ── DB health ────────────────────────────────────────────────
    begin
      t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveRecord::Base.connection.execute('SELECT 1')
      @db_ping_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) * 1000).round(1)
      @db_ok = true
    rescue => e
      @db_ok      = false
      @db_ping_ms = nil
    end

    # ── Background jobs ──────────────────────────────────────────
    jobs_24h        = GoodJob::Job.where(created_at: since..now)
    @jobs_total     = jobs_24h.count
    @jobs_succeeded = jobs_24h.where.not(finished_at: nil).where(error: nil).count
    @jobs_failed    = jobs_24h.where.not(error: nil).count
    @jobs_queued    = GoodJob::Job.where(finished_at: nil, performed_at: nil).count
    @jobs_running   = GoodJob::Job.where.not(performed_at: nil).where(finished_at: nil).count

    @recent_failures = GoodJob::Job
                         .where.not(error: nil)
                         .where(created_at: since..now)
                         .order(created_at: :desc)
                         .limit(6)
                         .select(:job_class, :created_at)

    # Jobs by hour
    raw_jobs = GoodJob::Job
                 .where(created_at: since..now)
                 .group(Arel.sql("DATE_TRUNC('hour', created_at)"))
                 .pluck(
                   Arel.sql("DATE_TRUNC('hour', created_at)"),
                   Arel.sql("SUM(CASE WHEN finished_at IS NOT NULL AND error IS NULL THEN 1 ELSE 0 END)"),
                   Arel.sql("SUM(CASE WHEN error IS NOT NULL THEN 1 ELSE 0 END)")
                 ) rescue []

    jobs_lookup = {}
    raw_jobs.each do |hr, succ, fail|
      jobs_lookup[hr.utc.beginning_of_hour.to_i] = [succ.to_i, fail.to_i]
    end

    # ── Activity logs ────────────────────────────────────────────
    @activity_total   = 0
    @activity_by_type = {}

    if ActiveRecord::Base.connection.table_exists?('activity_logs')
      al_base           = ActivityLog.where(created_at: since..now)
      @activity_total   = al_base.count
      @activity_by_type = al_base.group(:activity_type).count

      raw_al = ActivityLog
                 .where(created_at: since..now)
                 .group(Arel.sql("DATE_TRUNC('hour', created_at)"))
                 .pluck(Arel.sql("DATE_TRUNC('hour', created_at)"), Arel.sql("COUNT(*)")) rescue []

      al_lookup = {}
      raw_al.each { |hr, cnt| al_lookup[hr.utc.beginning_of_hour.to_i] = cnt }
    else
      al_lookup = {}
    end

    # ── External API logs ────────────────────────────────────────
    @api_stats = []
    if ActiveRecord::Base.connection.table_exists?('external_api_logs')
      raw_api = ExternalApiLog
                  .where(created_at: since..now)
                  .group(:service)
                  .pluck(
                    :service,
                    Arel.sql("COUNT(*)"),
                    Arel.sql("SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END)"),
                    Arel.sql("ROUND(AVG(duration_ms)::numeric, 1)")
                  ) rescue []

      @api_stats = raw_api.map do |svc, total, succ, avg|
        rate = total.to_i > 0 ? ((succ.to_f / total) * 100).round(1) : 0.0
        { service: svc, total: total.to_i, succeeded: succ.to_i,
          avg_ms: avg.to_f, success_rate: rate }
      end
    end

    # ── Price list sync ──────────────────────────────────────────
    @last_sync_at   = nil
    @sync_matched   = 0
    @sync_unmatched = 0
    @sync_partial   = 0
    @sync_total_run = 0
    @sync_match_pct = 0

    if ActiveRecord::Base.connection.table_exists?('ap_price_list_sync_logs')
      last_run_at = ApPriceListSyncLog.maximum(:run_at)
      if last_run_at
        @last_sync_at   = last_run_at
        run_logs        = ApPriceListSyncLog.where(run_at: last_run_at)
        @sync_matched   = run_logs.where(match_status: 'matched').count
        @sync_unmatched = run_logs.where(match_status: 'unmatched').count
        @sync_partial   = run_logs.where(match_status: 'partial').count
        @sync_total_run = run_logs.count
        @sync_match_pct = @sync_total_run > 0 ? (((@sync_matched + @sync_partial).to_f / @sync_total_run) * 100).round(1) : 0.0
      end
    end

    # ── Build 24-hour chart buckets ──────────────────────────────
    hours = []
    cur = since.utc.beginning_of_hour
    while cur <= now.utc.beginning_of_hour
      hours << cur
      cur += 1.hour
    end

    @chart_labels       = hours.map { |h| h.strftime('%H:%M') }
    @chart_activity     = hours.map { |h| al_lookup[h.to_i] || 0 }
    @chart_jobs_succ    = hours.map { |h| (jobs_lookup[h.to_i] || [0, 0])[0] }
    @chart_jobs_fail    = hours.map { |h| (jobs_lookup[h.to_i] || [0, 0])[1] }

    # ── Overall status ───────────────────────────────────────────
    failed_last_hour = GoodJob::Job
                         .where(created_at: 1.hour.ago..now)
                         .where.not(error: nil).count rescue 0

    @overall_status = if !@db_ok
                        'down'
                      elsif failed_last_hour > 3 || @jobs_queued > 20
                        'degraded'
                      else
                        'ok'
                      end

    @build_sha  = ENV.fetch('RENDER_GIT_COMMIT', nil)&.first(7)
    @checked_at = now
  end

  def authenticate
    if params[:pin].to_s.strip == PIN
      session[:status_pin_ok] = true
      redirect_to status_path
    else
      flash.now[:alert] = 'Incorrect PIN — try again.'
      render :pin, status: :unauthorized
    end
  end

  private

  def check_pin
    render :pin unless session[:status_pin_ok]
  end
end
