require 'sqlite3'
require 'bcrypt'
require 'net/http'

$hash = {}

$db = SQLite3::Database.new('db/users.db')
$db.results_as_hash = true

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

def requsetLifeTechServer(uri, response)
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
    password_digests = $db.execute('SELECT Password FROM User WHERE Username = ?', username)
    if BCrypt::Password.new(password_digests[0]['Password']) == password
      token = username.hash * password.hash * password_digests.hash * rand(2**256)
      $hash[token] = Time.now + 60 * 20
      return ModelResponse.new(true, token)
    else
      raise StandardError
    end
  rescue
    return ModelResponse.new(false, 'Användarnamnet eller lösenordet är felaktigt.')
  end
end

public def verifyLogin(token)
  begin
    if Time.now <= $hash[token]
      $hash[token] = Time.now + 60 * 20
      return ModelResponse.new(true, token)
    end
  rescue
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
      $db.execute('INSERT INTO User (GroupId, Password, Username) VALUES (?,?,?)',groupId ,passwordDigest, username)
    rescue
      errors << 'Användarnamnet är upptaget.'
    end
  end
  if !errors.empty?
    return ModelResponse.new(false, errors.join("\n"))
  end
  return ModelResponse.now(true, nil)
end
