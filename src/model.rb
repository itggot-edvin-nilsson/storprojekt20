# The model part of M.V.C.
module Model
  require 'sqlite3'
  require 'bcrypt'
  require 'net/http'

  $tokens = {}

  $dbUsers = SQLite3::Database.new('db/users.db')
  $dbUsers.results_as_hash = true

  $dbSensors = SQLite3::Database.new('db/sensors.db')
  $dbSensors.results_as_hash = true

  # Class that containins if the function were successful and data
  # @attr [Boolean] successful If the request was successful
  # @attr [Object] data Any extra data depending on the request
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

  # Get all groups
  # @return [Array<SQLite3::ResultSet::HashWithTypesAndFields>] the groups, the hash contains the keys 'GroupId' and 'Name'
  def getGroups()
    return $dbUsers.execute('SELECT * FROM Groups')
  end

  # Get all permissions
  # @return [Array<SQLite3::ResultSet::HashWithTypesAndFields>] the permissions, the hash contains the keys 'PermissionId', 'Name' and 'Path'
  def getPermissions()
    return $dbUsers.execute('SELECT * FROM Permissions')
  end

  # Get all sensors
  # @return [Array<SQLite3::ResultSet::HashWithTypesAndFields>] the sensors, the hash contains the keys'SensorId', 'SensorTypeId', 'Bus', 'Address', 'Command' and 'BoxId'
  def getSensors()
    sensors = $dbSensors.execute('SELECT * FROM Sensors')
    sensors = [{"SensorId"=>nil, "SensorTypeId"=>nil, "Bus"=>nil, "Address"=>nil, "Command"=>nil, "BoxId"=>nil}] if sensors.empty?
    return sensors
  end

  # Get all sensor types
  # @return [Array<SQLite3::ResultSet::HashWithTypesAndFields>] the sensor types, the hash contains the keys 'SensorTypeId' and 'FlowSensor'
  def getSensorsTypes()
    return $dbSensors.execute('SELECT * FROM SensorTypes')
  end

  # Get all habitats
  # @return [Array<SQLite3::ResultSet::HashWithTypesAndFields>] the habitats, the hash contains the keys 'HabitatId' and 'Name'
  def getHabitats()
    return $dbSensors.execute('SELECT * FROM Habitats')
  end

  # Get all users
  # @return [Array<SQLite3::ResultSet::HashWithTypesAndFields>] the users, the hash contains the keys 'UserId', 'GroupId' and 'Username'
  def getUsers()
    return $dbUsers.execute('SELECT * FROM Users')
  end


  # Delete user with user id
  # @param userId [Int] user id of user
  # @return [void]
  def deleteUser(userId)
    $dbUsers.execute('DELETE FROM Users WHERE UserId = ?', userId)
    $tokens.reject! {|x, y| y[1] == userId}
  end

  # Works like a proxy for requests to the LifeTech server
  # @param uri [URI] the uri
  # @param response [Sinatra::Response] reference to the sinatra response
  # @return [void]
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

  # Convert query string to number for the data period, like a enum
  # 'timme' => 1, 'dygnet' => 2, 'veckan' => 3, 'all' => 4, default => 0
  # @param queryString [String] the string to convert
  # @return [Int] a int that represents a data period
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

  # Generates a login token
  # @return [Int] a new token
  def generateToken()
    while true
      token = rand(2**512)
      return token unless $tokens.include?(token)
    end
  end

  # Login a user
  # @param username [String] the username
  # @param password [password] the password
  # @return [Model::ModelResponse] a model response, extra data is the token (Int) if successful, otherwise the error message (String)
  public def login(username, password)
    begin
      result = $dbUsers.execute('SELECT Password, UserId FROM Users WHERE Username = ?', username)
      if BCrypt::Password.new(result[0]['Password']) == password
        token = generateToken()
        $tokens[token] = [Time.now + 60 * 10, result[0]['UserId']]
        return ModelResponse.new(true, token)
      else
        raise StandardError
      end
    rescue => error
      p error
      return ModelResponse.new(false, 'Användarnamnet eller lösenordet var felaktigt.')
    end
  end

  # Check if user with token have permission for a specific permission id
  # @param permissionId [Int] the permission id to check
  # @param token [Int] the token the logged in user
  # @return [Boolean] if you have permission
  def havePermissionFor(permissionId, token)
    return true if permissionId.nil?
    userId = getUserId(token)
    return false if userId.nil?
    permissionIds = $dbUsers.execute('SELECT GroupPermissionRelation.PermissionId FROM GroupPermissionRelation ' +
      'INNER JOIN Users ON GroupPermissionRelation.GroupId = Users.GroupId WHERE Users.UserId = ?', userId)
      .map { |x| x['PermissionId'] }
    return permissionIds.include?(permissionId)
  end

  # Check if a group have permission for a specific permission id
  # @param permissionId [Int] the permission id to check
  # @param groupId [Int] the group id to check
  # @return [Boolean] if you have permission
  def havePermissionForGroup(permissionId, groupId)
    permissionIds = $dbUsers.execute('SELECT PermissionId FROM GroupPermissionRelation WHERE GroupId = ?', groupId).map { |x| x['PermissionId'] }
    return permissionIds.include?(permissionId)
  end

  # Toggle permission for a group
  # @param permissionId [Int] the permission id to toggle
  # @param groupId [Int] the group id
  # @return [void]
  def togglePermission(permissionId, groupId)
    $dbUsers.execute('DELETE FROM GroupPermissionRelation WHERE GroupId = ? AND PermissionId = ?', groupId, permissionId)
    $dbUsers.execute('INSERT INTO GroupPermissionRelation (GroupId, PermissionId) VALUES (?,?)', groupId, permissionId) if $dbUsers.changes == 0
  end

  # Get regular expression for checking permissions for paths
  # @return [String] a regular expression
  def getPermissionPathsAsRegex()
    paths = $dbUsers.execute('SELECT Path FROM Permissions').map { |x| x['Path'].sub!('/', '\/') }
    return /(#{paths.join('|')})(\/.*|)/
  end

  # Get permission id for a path origin
  # @param pathOrigin [String] the path origin to check
  # @return [Int, nil] the permission id
  def getPermissionId(pathOrigin)
    results = getPermissions()
    results.each do |result|
      if result['Path'] == pathOrigin
        return result['PermissionId']
      end
    end
    return nil
  end

  # Verify if a token is valid and if the user have the permission for a path origin
  # @param token [Int] the user token
  # @param pathOrigin [String] the path origin, for example '/sensor'
  # @return [Model::ModelResponse] a model response, extra data is the token (Int) if successful, otherwise the error message (String)
  public def verifyLogin(token, pathOrigin)
    begin
      if Time.now <= $tokens[token][0]
        newToken = generateToken()
        $tokens[newToken] = $tokens.delete(token)
        $tokens[newToken][0] = Time.now + 60 * 10

        permissionId = getPermissionId(pathOrigin)

        if permissionId != nil
          return ModelResponse.new(false, "Du har inte behörighet för att göra eller visa detta.") if !havePermissionFor(permissionId, newToken)
        end

        return ModelResponse.new(true, newToken)
      end
    rescue => error
      p error
    end
    return ModelResponse.new(false, nil)
  end

  # Check if password meets the requirements
  # @param [String] password to check
  # @return [Array<String>] a array with error messages
  def passwordCheck(password)
    errors = []
    errors << 'Lösenordet måste åtminstone vara sex tecken långt.'if password.length < 6
    return errors
  end

  # Register a new user
  # @param username [String] the username
  # @param password [String] the password
  # @param password2 [String] the password confirmation
  # @param groupId [Int] the group id
  # @return [Model::ModelResponse] a model response, extra data is error message (String) if not successful, otherwise nil
  public def register(username, password, password2, groupId)
    errors = []
    errors << 'Lösenorden överensstämmer inte.' if (password != password2)
    errors << 'Användarnamnet måste vara mellan ett och 1000 tecken.' if (username.empty? || username.length > 1000)
    errors.concat(passwordCheck(password))

    if errors.empty?
      passwordDigest = BCrypt::Password.create(password)
      begin
        $dbUsers.execute('INSERT INTO Users (GroupId, Password, Username) VALUES (?,?,?)', groupId, passwordDigest, username)
      rescue
        errors << 'Användarnamnet är upptaget.'
      end
    end
    if !errors.empty?
      return ModelResponse.new(false, errors.join("\n"))
    end
    return ModelResponse.new(true, nil)
  end

  # Get user id from token
  # @param token [Int] the login token
  # @return [Int, nil] a user id
  public def getUserId(token)
    begin
      return $tokens[token][1]
    rescue
      return nil
    end
  end

  # @param userId [Int]
  # @return [Array<SQLite3::ResultSet::HashWithTypesAndFields>] the user info, the hash contains the keys 'UserId', 'GroupId', 'Password' and 'Username'
  def getUserInfo(userId)
    $dbUsers.execute('SELECT * FROM Users WHERE UserId = ?', userId)[0]
  end

  # Update password for user with token
  # @param oldPassword [String] the old password
  # @param newPassword [String] the new password
  # @param newPassword2 [String] the new password confirmation
  # @param token [Int] the token for the user
  # @return [Model::ModelResponse] a model response, extra data is error message (String) if not successful, otherwise nil
  public def updatePassword(oldPassword, newPassword, newPassword2, token)
    errors = []
    begin

      errors << 'Lösenorden överensstämmer inte.' if (newPassword != newPassword2)
      errors.concat(passwordCheck(newPassword))

      userId = getUserId(token)
      errors << 'Du är inte längre inloggad.' if userId.nil?
      result = $dbUsers.execute('SELECT Password FROM Users WHERE UserId = ?', userId)

      if BCrypt::Password.new(result[0]['Password']) == oldPassword
        if errors.empty?
          passwordDigest = BCrypt::Password.create(newPassword)
          $dbUsers.execute('UPDATE Users SET Password = ? WHERE UserId = ?', passwordDigest, userId)
        end
      else
        errors << 'Det nuvarande lösenordet var felaktigt.'
      end
    rescue => e
      errors << 'Något gick snett.'
    end

    if !errors.empty?
      return ModelResponse.new(false, errors.join("\n"))
    end
    return ModelResponse.new(true, nil)
  end

  # Save sensors
  # @param params [Sinatra::IndifferentHash] a reference to Sinatra params
  # @return [Model::ModelResponse] a model response, extra data is error message (String) if not successful
  def saveSensors(params)
    bindVars = params.values[0...-1].each_slice(6)

    $dbSensors.execute('DELETE FROM Sensors')

    stmt = $dbSensors.prepare('INSERT INTO Sensors (SensorId, SensorTypeId, Bus, Address, Command, HabitatId) VALUES (?, ?, ?, ?, ?, ?)')

    bindVars.each do |bindVar|
      stmt.execute(bindVar)
    end

    errors = []
    errors << "Sensor ID:n behöver vara unika." if bindVars.map { |c| c[0] }.uniq.length != bindVars.count
    errors << "Åtminstone en I2C bus saknas." if bindVars.any? { |c| c[2] == "" }
    errors << "Åtminstone en address saknas." if bindVars.any? { |c| c[3] == "" }
    errors << "Åtminstone ett kommando saknas." if bindVars.any? { |c| c[4] == "" }
    errors << "Åtminstone ett habitat saknas." if bindVars.any? { |c| c[5] == "" }

    return ModelResponse.new(errors.empty?, errors.join(' '))
  end

  # Get error message from session and expend it
  # @param session [Rack::Session::Abstract::PersistedSecure::SecureSessionHash] a reference to Sinatra session
  # @return [String, nil] the error message
  def getError(session)
    error = session[:error]
    session[:error] = nil
    return error
  end
end

# Clear expired tokens from token-hash
# @return [void]
def clearExpiredTokens()
  Thread.new do
    while true
      sleep(5 * 60)
      $tokens.reject! {|x, y| y[0] < Time.now}
    end
  end
end