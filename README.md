Rack::Ratelimit
===============

* Run multiple rate limiters in a single app
* Scope each rate limit to certain requests: API, files, GET vs POST, etc.
* Apply each rate limit by request characteristics: IP, subdomain, OAuth2 token, etc.
* Flexible time window to limit burst traffic vs hourly or daily traffic:
    100 requests per 10 sec, 500 req/minute, 10000 req/hour, etc.
* Fast, low-overhead implementation in memcache using counters for discrete timeslices:
    timeslice = window * ceiling(current time / window)
    memcache.incr(counter for timeslice)


Configuration
-------------

Takes a block that classifies requests for rate limiting. Given a
Rack env, return a string such as IP address, API token, etc. If the
block returns nil, the request won't be rate-limited. If a block is
not given, all requests get the same limits.

Required configuration:
* rate: an array of [max requests, period in seconds]: [500, 5.minutes]

and one of
* cache: a Dalli::Client instance
* redis: a Redis instance
* counter: Your own custom counter. Must respond to `#increment(classification_string, end_of_time_window_timestamp)` and return the counter value after increment.

Optional configuration:
* name: name of the rate limiter. Defaults to 'HTTP'. Used in messages.
* conditions: array of procs that take a rack env, all of which must
    return true to rate-limit the request.
* exceptions: array of procs that take a rack env, any of which may
    return true to exclude the request from rate limiting.
* logger: responds to #info(message). If provided, the rate limiter
    logs the first request that hits the rate limit, but none of the
    subsequently blocked requests.
* error_message: the message returned in the response body when the rate
    limit is exceeded. Defaults to "<name> rate limit exceeded. Please
    wait <period> seconds then retry your request."


Examples
--------

Rate-limit bursts of POST/PUT/DELETE requests by IP address

    use(Rack::Ratelimit, name: 'POST',
      exceptions: ->(env) { env['REQUEST_METHOD'] == 'GET' },
      rate:   [50, 10.seconds],
      cache:  Dalli::Client.new,
      logger: Rails.logger) { |env| Rack::Request.new(env).ip }

Rate-limit API traffic by user (set by Rack::Auth::Basic)

    use(Rack::Ratelimit, name: 'API',
      conditions: ->(env) { env['REMOTE_USER'] },
      rate:   [1000, 1.hour],
      redis:  Redis.new(ratelimit_redis_config),
      logger: Rails.logger) { |env| env['REMOTE_USER'] }
