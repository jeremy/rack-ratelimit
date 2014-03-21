require 'rubygems'
require 'bundler/setup'
require 'minitest/autorun'

require 'rack/ratelimit'
require 'stringio'

class RatelimitTest < Minitest::Test
  def setup
    @cache = Dalli::Client.new('localhost:11211').tap(&:flush)
    @logger = Logger.new(@out = StringIO.new)

    @app = ->(env) { [200, {}, []] }

    @limited = Rack::Ratelimit.new(@app,
      name: :one, rate: [1, 10],
      cache: @cache, logger: @logger) { |env| 'classification' }

    @two_limits = Rack::Ratelimit.new(@limited,
      name: :two, rate: [1, 10],
      cache: @cache, logger: @logger) { |env| 'classification' }
  end

  def test_name_defaults_to_HTTP
    app = Rack::Ratelimit.new(@app, rate: [1, 10], cache: @cache)
    status, headers, body = app.call({})
    assert_equal 200, status
    assert_match '"name":"HTTP"', headers['X-Ratelimit']
  end

  def test_sets_informative_header_when_rate_limit_isnt_exceeded
    status, headers, body = @limited.call({})
    assert_equal 200, status
    assert_match %r({"name":"one","period":10,"limit":1,"remaining":1,"until":".*"}), headers['X-Ratelimit']
    assert_equal '', @out.string
  end

  def test_sets_multiple_informative_headers_for_each_rate_limiter
    status, headers, body = @two_limits.call({})
    assert_equal 200, status
    info = headers['X-Ratelimit'].split("\n")
    assert_equal 2, info.size
    assert_match %r({"name":"one","period":10,"limit":1,"remaining":1,"until":".*"}), info.first
    assert_match %r({"name":"two","period":10,"limit":1,"remaining":1,"until":".*"}), info.last
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
    assert_match /one: classification exceeded 1 request limit for/, @out.string
  end

  def test_optional_response_status
    app = Rack::Ratelimit.new(@app, rate: [1, 10], status: 503, cache: @cache)
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
    app = Rack::Ratelimit.new(@app, rate: [1, 10], cache: @cache)
    assert_rate_limited app.call({})
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
    app = Rack::Ratelimit.new(@app, rate: [1, 10], cache: @cache,
      conditions: ->(env) { env['c1'] }) { |env| 'classification' }
    assert_rate_limited app.call('c1' => true)
    assert_not_rate_limited app.call('c1' => false)
  end

  def test_skip_rate_limiting_when_classifier_returns_nil
    app = Rack::Ratelimit.new(@app, rate: [1, 10], cache: @cache) { |env| env['c'] }
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
end
