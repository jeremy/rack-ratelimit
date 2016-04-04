Gem::Specification.new do |s|
  s.name    = 'rack-ratelimit'
  s.version = '1.1.0'
  s.author  = 'Jeremy Daer'
  s.email   = 'jeremydaer@gmail.com'
  s.summary = 'Flexible rate limits for your Rack apps'
  s.license = 'MIT'

  s.required_ruby_version = '>= 1.8'

  s.add_dependency 'rack'

  # Optional dependencies. Use Memcached or Redis.
  s.add_development_dependency 'dalli'
  s.add_development_dependency 'redis'

  # Actual dev-only deps.
  s.add_development_dependency 'rake'
  s.add_development_dependency 'minitest', '~> 5.3.0'

  s.files = Dir["#{File.dirname(__FILE__)}/lib/**/*"]
end
