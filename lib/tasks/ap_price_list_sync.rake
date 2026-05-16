# lib/tasks/ap_price_list_sync.rake
namespace :ap do
  desc "Enrich Asian Paints products from staged price list rows. " \
       "Options: import_batch_id=<id>  user_id=<id>"
  task price_list_sync: :environment do
    import_batch_id     = ENV['import_batch_id'].presence&.to_i
    triggered_by_user_id = ENV['user_id'].presence&.to_i

    Rails.logger.info "[ap:price_list_sync] Enqueuing ApPriceListSyncJob " \
                      "(batch=#{import_batch_id.inspect}, user=#{triggered_by_user_id.inspect})"

    ApPriceListSyncJob.perform_later(
      import_batch_id:      import_batch_id,
      triggered_by_user_id: triggered_by_user_id
    )

    puts "ApPriceListSyncJob enqueued."
  end

  desc "Run ApPriceListSyncJob synchronously (use for debugging only)"
  task price_list_sync_now: :environment do
    import_batch_id      = ENV['import_batch_id'].presence&.to_i
    triggered_by_user_id = ENV['user_id'].presence&.to_i

    puts "Running ApPriceListSyncJob inline …"
    ApPriceListSyncJob.perform_now(
      import_batch_id:      import_batch_id,
      triggered_by_user_id: triggered_by_user_id
    )
    puts "Done."
  end
end
