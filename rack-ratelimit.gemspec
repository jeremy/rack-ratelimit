Gem::Specification.new do |s|
  s.name      = 'rack-ratelimit'
  s.version   = '1.2.1'
  s.author    = 'Jeremy Daer'
  s.email     = 'jeremydaer@gmail.com'
  s.homepage  = 'https://github.com/jeremy/rack-ratelimit'
  s.summary   = 'Flexible rate limits for your Rack apps'
  s.license   = 'MIT'

  s.required_ruby_version = '>= 2.0'

  s.files = Dir["#{File.dirname(__FILE__)}/lib/**/*"]
end
