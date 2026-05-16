# app/controllers/admin/system_processes_controller.rb
class Admin::SystemProcessesController < Admin::BaseController

  PER_PAGE = 30

  def index
    # ── Date filter ───────────────────────────────────────────────
    @date_from = parse_date(params[:date_from], Date.today)
    @date_to   = parse_date(params[:date_to],   Date.today)
    @date_to   = Date.today if @date_to > Date.today
    date_range  = @date_from.beginning_of_day..@date_to.end_of_day

    # ── GoodJob stats ─────────────────────────────────────────────
    jobs_base       = GoodJob::Job.where(created_at: date_range)
    @jobs_queued    = jobs_base.where(finished_at: nil, performed_at: nil).count
    @jobs_running   = jobs_base.where.not(performed_at: nil).where(finished_at: nil).count
    @jobs_succeeded = jobs_base.where.not(finished_at: nil).where(error: nil).count
    @jobs_discarded = jobs_base.where(error_event: 5).count
    @jobs_errored   = jobs_base.where.not(error: nil).where.not(finished_at: nil).count

    # ── Recent jobs (paginated) ────────────────────────────────────
    @tab  = params[:tab] || 'jobs'
    @page = [params[:page].to_i, 1].max

    @jobs = case params[:filter]
            when 'queued'    then GoodJob::Job.where(finished_at: nil, performed_at: nil)
            when 'running'   then GoodJob::Job.where.not(performed_at: nil).where(finished_at: nil)
            when 'failed'    then GoodJob::Job.where.not(error: nil).where.not(finished_at: nil)
            when 'succeeded' then GoodJob::Job.where.not(finished_at: nil).where(error: nil)
            else                  GoodJob::Job.all
            end
    @jobs = @jobs.where(created_at: date_range)
    @jobs_total = @jobs.count
    @jobs_pages = [(@jobs_total.to_f / PER_PAGE).ceil, 1].max
    @jobs = @jobs.order(created_at: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

    # ── External API logs ──────────────────────────────────────────
    api_base         = ExternalApiLog.where(created_at: date_range)
    @api_total_calls  = api_base.count
    @api_success_calls = api_base.succeeded.count
    @api_error_calls  = api_base.failed.count
    @api_avg_ms       = api_base.where.not(duration_ms: nil).average(:duration_ms)&.round(1)

    @api_logs = api_base.order(created_at: :desc)
    @api_logs = @api_logs.where(operation: params[:operation]) if params[:operation].present?
    @api_logs = @api_logs.where(status: params[:api_status])   if params[:api_status].present?
    @api_logs_total = @api_logs.count
    @api_logs_pages = [(@api_logs_total.to_f / PER_PAGE).ceil, 1].max
    @api_logs = @api_logs.includes(:organisation).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

    # ── Job class breakdown ────────────────────────────────────────
    @job_class_stats = GoodJob::Job
                         .where(created_at: date_range)
                         .group(:job_class)
                         .select('job_class,
                                  COUNT(*) AS total,
                                  SUM(CASE WHEN finished_at IS NOT NULL AND error IS NULL THEN 1 ELSE 0 END) AS succeeded,
                                  SUM(CASE WHEN error IS NOT NULL THEN 1 ELSE 0 END) AS errored,
                                  AVG(EXTRACT(EPOCH FROM (finished_at - performed_at)) * 1000) AS avg_ms')
                         .order('total DESC')
                         .to_a rescue []

    # ── API service breakdown ──────────────────────────────────────
    @api_service_stats = ExternalApiLog
                           .where(created_at: date_range)
                           .group(:service, :operation)
                           .select('service, operation,
                                    COUNT(*) AS total,
                                    SUM(CASE WHEN status = \'success\' THEN 1 ELSE 0 END) AS succeeded,
                                    SUM(CASE WHEN status = \'error\' THEN 1 ELSE 0 END) AS errored,
                                    AVG(duration_ms) AS avg_ms')
                           .order('total DESC')
                           .to_a

    # ── Activity logs ─────────────────────────────────────────────
    if ActiveRecord::Base.connection.table_exists?('activity_logs')
      al_base = ActivityLog.all
      al_base = al_base.where(organisation_id: params[:al_org])      if params[:al_org].present?
      al_base = al_base.where(activity_type:   params[:al_type])     if params[:al_type].present?
      al_base = al_base.where(activity_subtype: params[:al_subtype]) if params[:al_subtype].present?
      al_base = al_base.where(created_at: date_range)

      @al_total        = al_base.count
      @al_pages        = [(@al_total.to_f / PER_PAGE).ceil, 1].max
      @activity_logs   = al_base.includes(:organisation, :user)
                                .order(created_at: :desc)
                                .offset((@page - 1) * PER_PAGE)
                                .limit(PER_PAGE)

      @al_type_counts  = ActivityLog
                           .where(created_at: date_range)
                           .group(:activity_type)
                           .count

      @al_organisations = Organisation.order(:name)
    end

    # ── Sales Activity & Tinting status ──────────────────────────────────
    if ActiveRecord::Base.connection.table_exists?('activity_logs')
      sa_org  = params[:sa_org]
      sa_base = ActivityLog.where(activity_type: 'sales', created_at: date_range)
      sa_base = sa_base.where(organisation_id: sa_org) if sa_org.present?

      @sa_logs_total   = sa_base.count
      @sa_logs_pages   = [(@sa_logs_total.to_f / PER_PAGE).ceil, 1].max
      @sa_logs         = sa_base.includes(:organisation, :user)
                                .order(created_at: :desc)
                                .offset((@page - 1) * PER_PAGE)
                                .limit(PER_PAGE)
      @sa_total_litres = sa_base.where.not(quantity_litres: nil).sum(:quantity_litres).to_f

      if params[:tab] == 'sales_activity'
        tinting_orgs    = Organisation.where("settings->>'tinting_prompt_enabled' = 'true'").order(:name)
        @tinting_status = tinting_orgs.filter_map do |org|
          threshold = org.settings['tinting_prompt_threshold_litres'].to_f
          total     = (org.tinting_litres_since_reset.values.sum rescue 0.0).round(2)
          { org: org, threshold: threshold, total_litres: total }
        end
      end
    end

    # ── Price List Sync logs ───────────────────────────────────────
    if ActiveRecord::Base.connection.table_exists?('ap_price_list_sync_logs')
      sync_base = ApPriceListSyncLog.where(run_at: date_range)

      @sync_total       = sync_base.count
      @sync_matched     = sync_base.where(match_status: 'matched').count
      @sync_partial     = sync_base.where(match_status: 'partial').count
      @sync_ambiguous   = sync_base.where(match_status: 'ambiguous').count
      @sync_unmatched   = sync_base.where(match_status: 'unmatched').count
      @sync_save_failed = sync_base.where(match_status: 'save_failed').count

      @sync_run_stats = sync_base
                          .group("DATE_TRUNC('hour', run_at)")
                          .select("DATE_TRUNC('hour', run_at) AS run_hour,
                                   COUNT(*) AS total,
                                   SUM(CASE WHEN match_status = 'matched' THEN 1 ELSE 0 END) AS matched,
                                   SUM(CASE WHEN match_status = 'unmatched' THEN 1 ELSE 0 END) AS unmatched")
                          .order('run_hour DESC')
                          .limit(24)
                          .to_a rescue []

      @sync_logs = sync_base.includes(:product, :run_by)
      @sync_logs = @sync_logs.where(match_status: params[:sync_status]) if params[:sync_status].present?
      @sync_logs = @sync_logs.where(rule_applied: params[:sync_rule].to_i) if params[:sync_rule].present?
      @sync_logs_total = @sync_logs.count
      @sync_logs_pages = [(@sync_logs_total.to_f / PER_PAGE).ceil, 1].max
      @sync_logs = @sync_logs.order(run_at: :desc)
                             .offset((@page - 1) * PER_PAGE)
                             .limit(PER_PAGE)
    end
  end

  # POST /admin/system_processes/send_test_email
  def send_test_email
    SystemReportMailer.daily_report(Date.today).deliver_now
    redirect_to admin_system_processes_path,
                notice: "Daily report sent to #{SystemReportMailer::RECIPIENTS.join(', ')}."
  rescue => e
    redirect_to admin_system_processes_path, alert: "Mail failed: #{e.message}"
  end

  private

  def parse_date(val, default)
    val.present? ? Date.parse(val) : default
  rescue ArgumentError
    default
  end

end
