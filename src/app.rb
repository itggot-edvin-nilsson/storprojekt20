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
  return slim(:'realtime/index', locals: {classes: classes})
end

get '/realtid/:request' do
  return requestLifeTechServer(URI("https://ntilifetech.ga/realtid/#{params[:request]}?#{request.query_string}"), response)
end

get '/kamera' do
  return slim(:'/camera/index')
end

get '/media' do
  return slim(:'/media/index')
end

get '/sensor' do
  return slim(:'/sensor/index', locals: {sensors: getSensors(), types: getSensorsTypes()})
end

after '/*' do
  session[:error] = nil if request.request_method == 'GET'
end

#User
get '/login' do
  return slim(:'user/index')
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

before /\/(register|update-password)/ do
  response = verifyLogin(session[:token])
  session[:token] = response.data
  if !response.successful
    session[:redirect] = request.path
    redirect('/login')
  end
end

get '/register' do
  return slim(:'user/add', locals: {groups: getGroups()})
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
  return slim(:'user/edit')
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

get '*' do
  status 404
  slim(:'404')
end