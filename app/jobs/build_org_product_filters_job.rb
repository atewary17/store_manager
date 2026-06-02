# app/jobs/build_org_product_filters_job.rb
#
# Rebuilds the product profile filter for every active organisation.
# Triggered manually by a super-admin from System Processes.
#
# Stores a run summary in Rails.cache so the System Processes UI can show
# the results immediately after the job completes.

class BuildOrgProductFiltersJob < ApplicationJob
  queue_as :low_priority

  CACHE_KEY     = 'org_product_filter_last_run'.freeze
  CACHE_EXPIRES = 7.days

  def perform(triggered_by_user_id: nil)
    started_at = Time.current
    orgs       = Organisation.active.order(:name)

    total     = 0
    new_count = 0
    updated   = 0
    failed    = 0
    org_results = []

    orgs.each do |org|
      begin
        result = OrgProductFilterService.call(org)
        total += 1
        if result[:new_filter]
          new_count += 1
        else
          updated += 1
        end
        org_results << {
          org_id:        org.id,
          org_name:      org.name,
          product_count: result[:filter]['product_count'],
          brands_count:  result[:filter]['brands'].size,
          categories_count: result[:filter]['categories'].size,
          status:        result[:new_filter] ? 'new' : 'updated'
        }
      rescue => e
        failed += 1
        org_results << {
          org_id:   org.id,
          org_name: org.name,
          status:   'failed',
          error:    e.message
        }
        Rails.logger.error "[BuildOrgProductFiltersJob] org ##{org.id} failed: #{e.message}"
      end
    end

    summary = {
      run_at:           started_at.iso8601,
      duration_s:       (Time.current - started_at).round(1),
      triggered_by_id:  triggered_by_user_id,
      total_orgs:       total,
      new_filters:      new_count,
      updated_filters:  updated,
      failed:           failed,
      org_results:      org_results
    }

    Rails.cache.write(CACHE_KEY, summary, expires_in: CACHE_EXPIRES)

    Rails.logger.info "[BuildOrgProductFiltersJob] Done — #{total} orgs, " \
                      "#{new_count} new, #{updated} updated, #{failed} failed " \
                      "in #{summary[:duration_s]}s"
  end
end
