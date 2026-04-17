# config/puma.rb

# Puma worker threads — tune based on available RAM
# 1 GB RAM: workers 2, threads 2,4
# 4 GB RAM: workers 2, threads 2,8
workers ENV.fetch("WEB_CONCURRENCY") { 2 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 4 }
threads threads_count, threads_count

# Bind to all interfaces so Docker can proxy in
port        ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "development" }

# Needed for Puma cluster mode in production
preload_app!

# Reconnect DB connections after fork in cluster mode
on_worker_boot do
  ActiveSupport.on_load(:active_record) do
    ActiveRecord::Base.establish_connection
  end
end

# Allow Puma to be restarted by `rails restart`
plugin :tmp_restart
