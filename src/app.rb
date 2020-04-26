require 'sinatra'
require 'slim'
require_relative './model.rb'
include Model

enable :sessions
set :bind, '0.0.0.0'
set :environment, :production

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
  return slim(:'/sensor/index', locals: {sensors: getSensors(), types: getSensorsTypes(), habitats: getHabitats(), title: 'Sensorer'})
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
  response = login(params[:username], params[:password], request)
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
before getPermissionPathsAsRegex() do
  pathOrigin = '/' + request.path.split('/')[1]
  response = verifyLogin(session[:token], pathOrigin)
  if !response.successful
    session[:token] = nil if response.data[1]
    if !response.data[0].nil?
      session[:error] = response.data[0]
      redirect('/error')
    else
      session[:redirect] = pathOrigin
      redirect('/login')
    end
  end
  session[:token] = response.data
end

# Show page for registering a new account
get '/register' do
  return slim(:'user/add', locals: {groups: getGroups(), title: 'Registrering'})
end

# Register a new account
post '/register' do
  response = register(params[:username], params[:password], params[:password2], params[:group].to_i, session[:token])
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

# Show page for admin tools
get '/admin' do
  return slim(:'admin/index', locals: {groups: getGroups(), title: 'Administratörsverktyg'})
end

# Show page for deleting users
get '/admin/user' do
  return slim(:'user/delete', locals: {users: getUsers(), title: 'Ta bort användare'})
end

# Delete user with user id
post '/admin/user/delete' do
  userId = params[:userId].to_i
  deleteUser(userId)
  redirect('/admin/user')
end

# Show page for changing permission for group
get '/admin/:id' do
  groupId = params[:id].to_i
  groupName = getGroups()[groupId - 1]['Name']
  return slim(:'admin/edit', locals: {permissions: getPermissions(), groupId: groupId, groupName: groupName, title: "Behörigheter för grupp: #{groupName}"})
end

# Toggle permission for a group
post '/admin/toggle' do
  groupId = params[:groupId].to_i
  permissionId = params[:permissionId].to_i
  togglePermission(permissionId, groupId)
  redirect("/admin/#{groupId}")
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

clearExpiredTokens()