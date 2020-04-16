require 'sinatra'
require 'slim'
require_relative './model.rb'
include Model

enable :sessions
set :bind, '0.0.0.0'

# Show the homepage
get '/' do
  return slim(:index)
end

# Show page for displaying realtime data from the system
get '/realtid' do
  classes = Array.new(5) {''}
  classes[getDataPeriod(params['senaste'])] = ' active'
  return slim(:'realtime/index', locals: {classes: classes, title: 'Realtidsdata'})
end

# Works like a proxy for requests to the LifeTech server.
# All sub-request for /realtid will be forwarded to the LifeTech server
get '/realtid/:request' do
  return requestLifeTechServer(URI("https://ntilifetech.ga/realtid/#{params[:request]}?#{request.query_string}"), response)
end

# Show page for displaying camera images
get '/kamera' do
  timestamps = requestLifeTechServer(URI("https://ntilifetech.ga/kamera"), response)
    .force_encoding('utf-8').encode.scan(/Bilden är tagen (.*?)\.</).map { |x| x[0] }
  return slim(:'/camera/index', locals: {title: 'Kamera', timestamps: timestamps})
end

# Show page for media about LifeTech
get '/media' do
  return slim(:'/media/index', locals: {title: 'Media'})
end

# Show page for configuring all sensors
get '/sensor' do
  return slim(:'/sensor/index', locals: {sensors: getSensors(), types: getSensorsTypes(), title: 'Sensorer'})
end

# Update the database with the latest changes
post '/sensor/save' do
  response = saveSensors(params)
  if response.successful
    redirect('/')
  else
    session[:error] = response.data
    redirect('/sensor')
  end
end

# Show page for user login
get '/login' do
  return slim(:'user/index', locals: {title: 'Inloggning'})
end

# Send username and password for user login
post '/login' do
  response = login(params[:username], params[:password])
  if response.successful
    session[:token] = response.data
    if session[:redirect]
      path = session[:redirect]
      session[:redirect] = nil
      redirect(path)
    else
      redirect('/')
    end
  else
    session[:error] = response.data
    redirect('/login')
  end
end

# Checks if the logged in user have the right permission to visit a page.
# It runs before /register, /update-password, /sensor, /sensor/save
before /\/(register|update-password|sensor|sensor\/save)/ do
  pathOrigin = '/' + request.path.split('/')[1]
  response = verifyLogin(session[:token], pathOrigin)
  if !response.successful
    if !response.data.nil?
      session[:error] = response.data
      redirect('/error')
    else
      session[:redirect] = pathOrigin
      redirect('/login')
    end
  else
    session[:token] = response.data
  end
end

# Show page for registering a new account
get '/register' do
  return slim(:'user/add', locals: {groups: getGroups(), title: 'Registrering'})
end

# Register a new account
post '/register' do
  response = register(params[:username], params[:password], params[:password2], params[:group].to_i)
  if response.successful
    redirect('/')
  else
    session[:error] = response.data
    redirect('/register')
  end
end

# Show page for changing password
get '/update-password' do
  return slim(:'user/edit', locals: {title: 'Ändra lösenord'})
end

# Update the logged in users password
post '/update-password' do
  response = updatePassword(params[:oldPassword], params[:newPassword], params[:newPassword2], session[:token])
  if response.successful
    redirect('/')
  else
    session[:error] = response.data
    redirect('/update-password')
  end
end

# Logout user and redirect to homepage
post '/logout' do
  session.destroy
  redirect('/')
end

# Show error message stored in session[:error]
get '/error' do
  redirect('/') if session[:error].nil?
  return slim(:error)
end

# Error 404 Page Not Found
get '*' do
  status 404
  slim(:'404')
end