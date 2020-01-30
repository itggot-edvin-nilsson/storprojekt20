require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'

enable :sessions

$db = SQLite3::Database.new('db/lists.db')
$db.results_as_hash = true

get('/') do
  return slim(:index)
end

get '/realtime' do
  return slim(:realtime)
end

get '/login' do
  return slim(:'login/index')
end

hash = {}

post('/login') do
  begin
    username = params[:username]
    password = params[:password]

    password_digests = $db.execute("SELECT Password FROM User WHERE Username = ?", username)

    if BCrypt::Password.new(password_digests[0]["Password"]) == password
      token = username.hash * password.hash * password_digests.hash * rand(Integer::MAX)
      hash[token] = Time.now + 60 * 60 * 24
      session[:token] = token
    end

  rescue
    p "Användarnamnet eller lösenordet är felaktigt."
  end
  redirect('/')
end