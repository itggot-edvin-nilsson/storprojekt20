require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'

enable :sessions

$db = SQLite3::Database.new('db/users.db')
$db.results_as_hash = true

get '/' do
  return slim(:index)
end

get '/realtime' do
  return slim(:'realtime/index')
end
#Error
get '/error' do
  return slim(:'error')
end

after '/error' do
  session[:error] = nil
end

#User
get '/login' do
  return slim(:'user/index')
end

hash = {}

post '/login' do
  begin
    username = params[:username]
    password = params[:password]

    password_digests = $db.execute('SELECT Password FROM User WHERE Username = ?', username)

    if BCrypt::Password.new(password_digests[0]['Password']) == password
      token = username.hash * password.hash * password_digests.hash * rand(2**64)
      hash[token] = Time.now + 60 * 20
      session[:token] = token
    end
  rescue
    session[:error] = 'Användarnamnet eller lösenordet är felaktigt.'
    redirect('/error')
    return
  end
  redirect('/')
end

def verify_login(token)
  if hash[token] < Time.now
    session[:token] = Time.now + 60 * 20
  end
end

get '/register' do
  return slim(:'user/add')
end

post '/register' do
  username = params[:username]
  password = params[:password]
  password2 = params[:password2]
  groupId = params[:group].to_i

  errors = []
  if (password != password2)
    errors << 'Lösenorden överensstämmer inte.'
  end
  if (username.empty? || username.length > 1000)
    errors << 'Användarnamnet måste vara mellan ett 1000 tecken.'
  end

  passwordDigest = BCrypt::Password.create(password)

  begin
    $db.execute('INSERT INTO User (GroupId, Password, Username) VALUES (?,?,?)',groupId ,passwordDigest, username)
  rescue
    errors << 'Användarnamn är upptaget.'
  end
  p errors
  if !errors.empty?
    session[:error] = errors.join("\n")
    redirect('/error')
    return
  end
  redirect('/register')
end