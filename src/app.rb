require 'sinatra'
require 'slim'
require_relative './model.rb'

enable :sessions
set :bind, '0.0.0.0'

get '/' do
  return slim(:index)
end

get '/realtid' do
  raise NotImplementedError
  classes = ['', '', '', '', '']
  case params['senaste']
  when 'timmen'
  when 'dygnet'
  when 'veckan'
  when 'all'
  else

  end
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

post '/login' do
  response = login(params[:username], params[:password])
  if response.successful
    session[:token] = response.data
    redirect('/')
  else
    session[:error] = response.data
    redirect('/error')
  end
end

before /\/(register|res)/ do
  response = verifyLogin(session[:token])
  p response
  session[:token] = response.data
  redirect('/login') if !response.successful
end

get '/register' do
  return slim(:'user/add')
end

post '/register' do
  response = register(params[:username], params[:password], params[:password2], params[:group].to_i)
  if response.successful
    redirect('/register')
  else
    session[:error] = response.data
    redirect('/error')
  end
end

post '/logout' do
  session.destroy
  redirect('/')
end