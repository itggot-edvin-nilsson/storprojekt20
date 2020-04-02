require 'sqlite3'
require 'bcrypt'
require 'net/http'

$hash = {}

$dbUsers = SQLite3::Database.new('db/users.db')
$dbUsers.results_as_hash = true

$dbSensors = SQLite3::Database.new('db/sensors.db')
$dbSensors.results_as_hash = true

class ModelResponse
  @successful
  @data
  def initialize(successful, data)
    @successful = successful
    @data = data
  end
  def successful; @successful end
  def data; @data end
end

def requestLifeTechServer(uri, response)
  Net::HTTP.start(uri.host, uri.port,
                  :use_ssl => uri.scheme == 'https') do |http|
    request = Net::HTTP::Get.new uri
    httpResponse = http.request request
    response.status = httpResponse.code
    return httpResponse.body
  end
  response.status = 408
end

def getDataPeriod(queryString)
  case queryString
  when 'timmen'
    return 1
  when 'dygnet'
    return 2
  when 'veckan'
    return 3
  when 'all'
    return 4
  else
    return 0
  end
end

#Login
public def login(username, password)
  begin
    result = $dbUsers.execute('SELECT Password, UserId FROM Users WHERE Username = ?', username)
    if BCrypt::Password.new(result[0]['Password']) == password
      token = username.hash * password.hash * result.hash * rand(2**256)
      $hash[token] = [Time.now + 60 * 20, result[0]['UserId']]
      return ModelResponse.new(true, token)
    else
      raise StandardError
    end
  rescue => error
    p error
    return ModelResponse.new(false, 'Användarnamnet eller lösenordet var felaktigt.')
  end
end

def havePermissionFor(permissionId, token)
  userId = getUserId(token)
  permissionIds = $dbUsers.execute('SELECT GroupPermissionRelation.PermissionId FROM GroupPermissionRelation ' +
    'INNER JOIN Users ON GroupPermissionRelation.GroupId = Users.GroupId WHERE Users.UserId = ?', userId)
    .map { |x| x["PermissionId"] }
  return permissionIds.include?(permissionId)
end

public def verifyLogin(token, pathOrigin)
  begin
    if Time.now <= $hash[token][0]
      $hash[token][0] = Time.now + 60 * 20

      permissionId = nil

      results = $dbUsers.execute('SELECT PermissionId, Path FROM Permissions')
      results.each do |result|
        if result['Path'] == pathOrigin
          permissionId = result['PermissionId']
          break
        end
      end

      if permissionId != nil
        return ModelResponse.new(false, "Du har inte behörighet för att göra detta.") if !havePermissionFor(permissionId, token)
      end

      return ModelResponse.new(true, token)
    end
  rescue => error
    p error
  end
  return ModelResponse.new(false, nil)
end

public def register(username, password, password2, groupId)
  errors = []
  errors << 'Lösenorden överensstämmer inte.' if (password != password2)
  if (username.empty? || username.length > 1000)
    errors << 'Användarnamnet måste vara mellan ett och 1000 tecken.'
  else
    passwordDigest = BCrypt::Password.create(password)
    begin
      $dbUsers.execute('INSERT INTO Users (GroupId, Password, Username) VALUES (?,?,?)', groupId, passwordDigest, username)
    rescue
      errors << 'Användarnamnet är upptaget.'
    end
  end
  if !errors.empty?
    return ModelResponse.new(false, errors.join('\n'))
  end
  return ModelResponse.new(true, nil)
end

public def getUserId(token)
  return $hash[token][1]
end

public def updatePassword(oldPassword, newPassword, newPassword2, token)
  errors = []
  if (newPassword != newPassword2)
    errors << 'Lösenorden överensstämmer inte.'
    return ModelResponse.new(false, errors.join("\n"))
  end

  userId = getUserId(token)
  result = $dbUsers.execute('SELECT Password FROM Users WHERE UserId = ?', userId)

  if BCrypt::Password.new(result[0]['Password']) == oldPassword

    passwordDigest = BCrypt::Password.create(newPassword)
    begin
      $dbUsers.execute('UPDATE Users SET Password = ? WHERE UserId = ?', passwordDigest, userId)
    rescue
      errors << 'Något gick snett.'
    end
  else
    errors << 'Det nuvarande lösenordet var felaktigt.'
  end

  if !errors.empty?
    return ModelResponse.new(false, errors.join("\n"))
  end
  return ModelResponse.new(true, nil)
end

def getGroups()
  return $dbUsers.execute('SELECT * FROM Groups')
end

def getSensors()
  sensors = $dbSensors.execute('SELECT * FROM Sensors')
  sensors = [{"SensorId"=>nil, "SensorTypeId"=>nil, "Bus"=>nil, "Address"=>nil, "Command"=>nil, "BoxId"=>nil}] if sensors.empty?
  return sensors
end

def getSensorsTypes()
  return $dbSensors.execute('SELECT * FROM SensorTypes')
end

def saveSensors(params)
  bindVars = params.values[0...-1].each_slice(6)

  $dbSensors.execute('DELETE FROM Sensors')

  stmt = $dbSensors.prepare('INSERT INTO Sensors (SensorId, SensorTypeId, Bus, Address, Command, BoxId) VALUES (?, ?, ?, ?, ?, ?)')

  bindVars.each do |bindVar|
    stmt.execute(bindVar)
  end

  errors = []
  if bindVars.map { |c| c[0] }.uniq.length != bindVars.count
    errors << "Sensor ID:n behöver vara unika."
  end

  return ModelResponse.new(errors.empty?, errors.join(' '))
end

@error = public def getError(session)
  error = session[:error]
  session[:error] = nil
  return error
end