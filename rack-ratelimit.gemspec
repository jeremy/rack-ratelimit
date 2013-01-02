Gem::Specification.new do |s|
  s.name    = 'rack-ratelimit'
  s.version = '1.0.0'
  s.author  = 'Jeremy Kemper'
  s.email   = 'jeremy@bitsweat.net'
  s.summary = 'Flexible rate limits for your Rack apps'
  s.license = 'MIT'

  s.required_ruby_version = '>= 1.8'

  s.add_dependency 'rack'
  s.add_dependency 'dalli'

  s.add_development_dependency 'rake'
  s.add_development_dependency 'minitest'

  s.files = Dir["#{File.dirname(__FILE__)}/**/*"]
end
