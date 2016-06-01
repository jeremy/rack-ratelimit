require 'rubygems'
require 'bundler/setup'
require 'minitest/autorun'

require 'rack/ratelimit'
require 'stringio'
require 'json'

require 'dalli'
require 'redis'

module RatelimitTests
  def setup
    @app = ->(env) { [200, {}, []] }
    @logger = Logger.new(@out = StringIO.new)

    @limited = build_ratelimiter(@app, name: :one, rate: [1, 10])
    @two_limits = build_ratelimiter(@limited, name: :two, rate: [1, 10])
  end

  def test_name_defaults_to_HTTP
    app = build_ratelimiter(@app)
    assert_match '"name":"HTTP"', app.call({})[1]['X-Ratelimit']
  end

  def test_sets_informative_header_when_rate_limit_isnt_exceeded
    status, headers, body = @limited.call({})
    assert_equal 200, status
    assert_match %r({"name":"one","period":10,"limit":1,"remaining":0,"until":".*"}), headers['X-Ratelimit']
    assert_equal [], body
    assert_equal '', @out.string
  end

  def test_decrements_rate_limit_header_remaining_count
    app = build_ratelimiter(@app, rate: [3, 10])
    remainings = 5.times.map { JSON.parse(app.call({})[1]['X-Ratelimit'])['remaining'] }
    assert_equal [2,1,0,0,0], remainings
  end

  def test_sets_multiple_informative_headers_for_each_rate_limiter
    status, headers, body = @two_limits.call({})
    assert_equal 200, status
    info = headers['X-Ratelimit'].split("\n")
    assert_equal 2, info.size
    assert_match %r({"name":"one","period":10,"limit":1,"remaining":0,"until":".*"}), info.first
    assert_match %r({"name":"two","period":10,"limit":1,"remaining":0,"until":".*"}), info.last
    assert_equal [], body
    assert_equal '', @out.string
  end

  def test_responds_with_429_if_request_rate_exceeds_limit
    assert_equal 200, @limited.call('limit-by' => 'key').first
    status, headers, body = @limited.call('limit-by' => 'key')
    assert_equal 429, status
    assert_equal '10', headers['Retry-After']
    assert_match '0', headers['X-Ratelimit']
    assert_match %r({"name":"one","period":10,"limit":1,"remaining":0,"until":".*"}), headers['X-Ratelimit']
    assert_equal 'one rate limit exceeded. Please wait 10 seconds then retry your request.', body.first
    assert_match %r{one: classification exceeded 1 request limit for}, @out.string
  end

  def test_optional_response_status
    app = build_ratelimiter(@app, status: 503)
    assert_equal 200, app.call('limit-by' => 'key').first
    assert_equal 503, app.call('limit-by' => 'key').first
  end

  def test_doesnt_log_on_subsequent_rate_limited_requests
    assert_equal 200, @limited.call('limit-by' => 'key').first
    assert_equal 429, @limited.call('limit-by' => 'key').first
    out = @out.string.dup
    assert_equal 429, @limited.call('limit-by' => 'key').first
    assert_equal out, @out.string
  end

  def test_classifier_is_optional
    app = build_ratelimiter(@app, no_classifier: true)
    assert_rate_limited app.call({})
  end

  def test_classify_may_be_overridden
    app = build_ratelimiter(@app, no_classifier: true)
    def app.classify(env) env['limit-by'] end
    assert_equal 200, app.call('limit-by' => 'a').first
    assert_equal 200, app.call('limit-by' => 'b').first
  end

  def test_conditions_and_exceptions
    @limited.condition { |env| env['c1'] }
    @limited.condition { |env| env['c2'] }
    @limited.exception { |env| env['e1'] }
    @limited.exception { |env| env['e2'] }

    # Any exceptions exclude the request from rate limiting.
    assert_not_rate_limited @limited.call({ 'c1' => true, 'c2' => true, 'e1' => true })
    assert_not_rate_limited @limited.call({ 'c1' => true, 'c2' => true, 'e2' => true })

    # All conditions must be met to rate-limit the request.
    assert_not_rate_limited @limited.call({ 'c1' => true })
    assert_not_rate_limited @limited.call({ 'c2' => true })

    # If all conditions are met with no exceptions, rate limit.
    assert_rate_limited @limited.call({ 'c1' => true, 'c2' => true })
  end

  def test_conditions_and_exceptions_as_config_options
    app = build_ratelimiter(@app, conditions: ->(env) { env['c1'] })
    assert_rate_limited app.call('c1' => true)
    assert_not_rate_limited app.call('c1' => false)
  end

  def test_skip_rate_limiting_when_classifier_returns_nil
    app = build_ratelimiter(@app) { |env| env['c'] }
    assert_rate_limited app.call('c' => '1')
    assert_not_rate_limited app.call('c' => nil)
  end

  private
    def assert_not_rate_limited(response)
      assert_nil response[1]['X-Ratelimit']
    end

    def assert_rate_limited(response)
      assert !response[1]['X-Ratelimit'].nil?
    end

    def build_ratelimiter(app, options = {}, &block)
      block ||= -> env { 'classification' } unless options.delete(:no_classifier)
      Rack::Ratelimit.new(app, ratelimit_options.merge(options), &block)
    end

    def ratelimit_options
      { rate: [1,10], logger: @logger }
    end
end

class RequiredBackendTest < Minitest::Test
  def test_backend_is_required
    assert_raises ArgumentError do
      Rack::Ratelimit.new(nil, rate: [1,10])
    end
  end
end

class MemcachedRatelimitTest < Minitest::Test
  include RatelimitTests

  def setup
    @cache = Dalli::Client.new('localhost:11211').tap(&:flush)
    super
  end

  def teardown
    super
    @cache.close
  end

  private
    def ratelimit_options
      super.merge cache: @cache
    end
end

class RedisRatelimitTest < Minitest::Test
  include RatelimitTests

  def setup
    @redis = Redis.new(:host => 'localhost', :port => 6379, :db => 0).tap(&:flushdb)
    super
  end

  def teardown
    super
    @redis.quit
  end

  private
    def ratelimit_options
      super.merge redis: @redis
    end
end

class CustomCounterRatelimitTest < Minitest::Test
  include RatelimitTests

  private
    def ratelimit_options
      super.merge counter: Counter.new
    end

  class Counter
    def initialize
      @counters = Hash.new do |classifications, name|
        classifications[name] = Hash.new do |timeslices, timestamp|
          timeslices[timestamp] = 0
        end
      end
    end

    def increment(classification, timestamp)
      @counters[classification][timestamp] += 1
    end
  end
end
