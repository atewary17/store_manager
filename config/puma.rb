# config/puma.rb

# Puma worker threads — tune based on available RAM
# 1 GB RAM: workers 2, threads 2,4
# 4 GB RAM: workers 2, threads 2,8
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 4 }
threads threads_count, threads_count

# Bind to all interfaces so Docker can proxy in
port        ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "development" }

# Cluster mode (multiple workers) only in production.
# In development, a single-process threaded server is simpler and supports
# code reloading. WEB_CONCURRENCY defaults to 0 (off) unless explicitly set.
if ENV.fetch("RAILS_ENV", "development") == "production"
  workers ENV.fetch("WEB_CONCURRENCY") { 2 }

  # Needed for Puma cluster mode — boot app before forking workers
  preload_app!

  # Reconnect DB connections after fork
  on_worker_boot do
    ActiveSupport.on_load(:active_record) do
      ActiveRecord::Base.establish_connection
    end
  end
end

# Allow Puma to be restarted by `rails restart`
plugin :tmp_restart
