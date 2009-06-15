require 'rubygems'
require 'sinatra'

# a database is overkill, but lets us maintain a log of who has had staging
# and ensures transactionality
require 'sequel'
require 'logger'

configure do
  DB = Sequel.sqlite("has-staging.db", :loggers => [Logger.new("db.log")])
  unless DB.tables.include?(:staging_locks)
    DB.create_table :staging_locks do
      primary_key :id
      String :name, :null => false
      String :project, :null => false
      boolean :active, :default => true, :null => false
      Time :created_at
      Time :updated_at
    end
  end
end

helpers do
  include Rack::Utils
  def format_lock(lock)
    "#{escape_html lock[:name]} is using staging for #{escape_html lock[:project]} (#{escape_html lock[:updated_at]})"
  end
end

get '/' do
  locks = DB[:staging_locks].filter(:active => true).order(:updated_at.desc)
  current_lock = !(locks.empty?) ? locks.first : nil

  if current_lock
    format_lock(current_lock)
  else
    "No one is using staging right now."
  end
end

put '/:name' do
  DB.transaction do
    locks = DB[:staging_locks].filter(:active => true).order(:updated_at.desc)
    current_lock = !(locks.empty?) ? locks.first : nil
        
    name, project = params[:name], params[:project]

    if @current_lock
      halt 409, format_lock(lock)
    else
      insert_time = Time.now.utc
      DB[:staging_locks].insert(:name => name, :project => project,
                :updated_at => insert_time, 
                :created_at => insert_time)
      "Lock taken"
    end
  end
end

delete '/:name' do
  DB.transaction do
    name = params[:name]
    lock = DB[:staging_locks].filter(:active => true, :name => name)
    if !(lock.empty?)
      lock.update(:active => false, :updated_at => Time.now.utc)
      "Lock released"
    else
      halt 404, "Lock not found"
    end
  end
end
