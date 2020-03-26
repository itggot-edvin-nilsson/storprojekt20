require 'sinatra'
require 'slim'
require_relative './model.rb'

enable :sessions
set :bind, '0.0.0.0'

get '/' do
  return slim(:index)
end

get '/realtid' do
  classes = Array.new(5) {''}
  classes[getDataPeriod(params['senaste'])] = ' active'
  return slim(:'realtime/index', locals: {classes: classes, title: 'Realtidsdata'})
end

get '/realtid/:request' do
  return requestLifeTechServer(URI("https://ntilifetech.ga/realtid/#{params[:request]}?#{request.query_string}"), response)
end

get '/kamera' do
  return slim(:'/camera/index', locals: {title: 'Kamera'})
end

get '/media' do
  return slim(:'/media/index', locals: {title: 'Media'})
end

get '/sensor' do
  return slim(:'/sensor/index', locals: {sensors: getSensors(), types: getSensorsTypes(), title: 'Sensorer'})
end

post '/sensor/save' do
  response = saveSensors(params)
  if response.successful
    redirect('/')
  else
    session[:error] = response.data
    redirect('/sensor')
  end
end

=begin
after '/*' do
  session[:error] = nil if request.request_method == 'GET'
end
=end

#User
get '/login' do
  return slim(:'user/index', locals: {title: 'Inloggning'})
end

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

before /\/(register|update-password|sensor|sensor\/save)/ do
  pathOrigin = '/' + request.path.split('/')[1]
  response = verifyLogin(session[:token], pathOrigin)
  session[:token] = response.data
  if !response.successful
    if !response.data.nil?
      session[:error] = response.data
      redirect('/error')
    end

    session[:redirect] = pathOrigin
    redirect('/login')
  end
end

get '/register' do
  return slim(:'user/add', locals: {groups: getGroups(), title: 'Registrering'})
end

post '/register' do
  response = register(params[:username], params[:password], params[:password2], params[:group].to_i)
  if response.successful
    redirect('/')
  else
    session[:error] = response.data
    redirect('/register')
  end
end

get '/update-password' do
  return slim(:'user/edit', locals: {title: 'Ändra lösenord'})
end

post '/update-password' do
  response = updatePassword(params[:oldPassword], params[:newPassword], params[:newPassword2], session[:token])
  if response.successful
    redirect('/')
  else
    session[:error] = response.data
    redirect('/update-password')
  end
end

post '/logout' do
  session.destroy
  redirect('/')
end

get '/error' do
  redirect('/') if session[:error].nil?
  return slim(:error)
end

get '*' do
  status 404
  slim(:'404')
end