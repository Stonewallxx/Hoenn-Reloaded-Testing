#======================================================
# Reloaded Remote Data
# Author: Stonewall
#======================================================
# Shared safe retrieval and last-known-good caching for small text/JSON data.
# Binary downloads and background task management are intentionally separate.
#======================================================

begin
  require "json"
rescue Exception
end

begin
  require "net/http"
  require "uri"
  require "time"
rescue Exception
end

module Reloaded
  module RemoteData
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    CACHE_ROOT = File.join(ROOT, "Cache", "RemoteData")
    FORMATS = [:text, :json].freeze
    DEFAULT_TIMEOUT = 8
    DEFAULT_RETRIES = 1
    DEFAULT_REDIRECT_LIMIT = 5
    DEFAULT_MAX_BYTES = 2_000_000
    USER_AGENT = "Hoenn Reloaded RemoteData"
    REDIRECT_CODES = [301, 302, 303, 307, 308].freeze
    RETRYABLE_CODES = [408, 429, 500, 502, 503, 504].freeze

    class Result
      attr_reader :value, :body, :source, :status, :fetched_at, :loaded_at,
                  :cache_age, :http_status, :attempts, :error_code,
                  :error_message, :source_id, :url_label, :server_time

      def initialize(options = {})
        @ok = !!options[:ok]
        @value = options[:value]
        @body = options[:body]
        @source = (options[:source] || :none).to_sym
        @status = (options[:status] || (@ok ? :fresh : :failed)).to_sym
        @fetched_at = options[:fetched_at].to_i
        @loaded_at = options[:loaded_at].to_i
        @cache_age = options[:cache_age].to_i
        @stale = !!options[:stale]
        @http_status = options[:http_status].to_i
        @attempts = options[:attempts].to_i
        @error_code = options[:error_code] && options[:error_code].to_sym
        @error_message = options[:error_message].to_s
        @source_id = options[:source_id] && options[:source_id].to_sym
        @url_label = options[:url_label].to_s
        @remote_confirmed = !!options[:remote_confirmed]
        @server_time = options[:server_time].to_i
      end

      def ok?
        @ok
      end

      def stale?
        @stale
      end

      def fallback?
        @status == :fallback
      end

      def remote_confirmed?
        @remote_confirmed
      end
    end

    @sources = {}
    @transport_override = nil

    class << self
      def register(id, options = {})
        key = normalize_id(id)
        raise "Remote data source ID is empty." unless key
        owner = normalize_id(options[:owner] || :reloaded)
        existing = @sources[key]
        if existing && existing[:owner] != owner
          raise "Remote data source #{key} is already owned by #{existing[:owner]}."
        end
        source = normalize_source(key, owner, options)
        @sources[key] = source
        key
      rescue Exception => e
        log_exception("Remote data registration failed", e)
        raise
      end

      def registered?(id)
        !!@sources[normalize_id(id)]
      rescue
        false
      end

      def source(id)
        value = @sources[normalize_id(id)]
        value ? public_source(value) : nil
      rescue
        nil
      end

      def sources
        result = {}
        @sources.each { |id, value| result[id] = public_source(value) }
        result
      end

      def registered_cache_paths
        @sources.values.map { |source| source[:cache_path] }.compact.map do |path|
          File.expand_path(path.to_s)
        end.uniq
      rescue
        []
      end

      def unregister_owner(owner)
        owner_id = normalize_id(owner)
        removed = @sources.keys.select { |id| @sources[id][:owner] == owner_id }
        removed.each { |id| @sources.delete(id) }
        removed
      rescue
        []
      end

      def fetch(id, options = {})
        source = source_config!(id)
        return fallback_result(source, :unsupported, "Remote data is unavailable on this platform.") unless remote_supported?
        fetch_remote(source, options)
      rescue Exception => e
        log_exception("Remote data fetch failed for #{safe_id(id)}", e)
        failed_result(id, :exception, e.message)
      end

      def load(id)
        source = source_config!(id)
        cached = cache_result(source)
        return cached if cached
        local = local_result(source)
        return local if local
        failed_result(source[:id], :unavailable, "No valid cached or local data is available.")
      rescue Exception => e
        log_exception("Remote data load failed for #{safe_id(id)}", e)
        failed_result(id, :exception, e.message)
      end

      def load_cached(id)
        source = source_config!(id)
        result = cache_result(source)
        result || failed_result(source[:id], :cache_unavailable, "No valid cached data is available.")
      rescue Exception => e
        failed_result(id, :cache_error, e.message)
      end

      def load_local(id)
        source = source_config!(id)
        result = local_result(source)
        result || failed_result(source[:id], :local_unavailable, "No valid local data is available.")
      rescue Exception => e
        failed_result(id, :local_error, e.message)
      end

      def clear(id)
        source = source_config!(id)
        path = source[:cache_path]
        File.delete(path) if path && File.file?(path)
        File.delete("#{path}.tmp") if path && File.file?("#{path}.tmp")
        File.delete("#{path}.bak") if path && File.file?("#{path}.bak")
        true
      rescue Exception => e
        log_exception("Remote data cache clear failed for #{safe_id(id)}", e)
        false
      end

      def fetch_text(url, options = {})
        fetch_transient(:text, url, options)
      end

      def fetch_json(url, options = {})
        fetch_transient(:json, url, options)
      end

      def key_for(prefix, value)
        text = value.to_s
        hash = 2_166_136_261
        text.each_byte do |byte|
          hash ^= byte
          hash = (hash * 16_777_619) & 0xffffffff
        end
        "#{safe_key(prefix)}_#{format('%08x', hash)}".to_sym
      end

      # Internal test seam. Production callers should register sources instead.
      def transport_override=(callback)
        @transport_override = callback
      end

      def parse_json_document(raw)
        parse_json(raw)
      end

      private

      def fetch_transient(format, url, options)
        id = options[:id] || key_for(format, "#{url}|#{options[:headers].inspect}")
        register(id, {
          :owner => options[:owner] || :remote_data,
          :format => format,
          :urls => [{ :url => url, :headers => options[:headers] || {}, :label => options[:label] }],
          :cache_path => options[:cache_path],
          :local_path => options[:local_path],
          :timeout => options[:timeout],
          :retries => options[:retries],
          :redirect_limit => options[:redirect_limit],
          :max_bytes => options[:max_bytes],
          :ttl => options[:ttl],
          :allow_empty => options[:allow_empty],
          :validator => options[:validator]
        })
        options[:remote] == false ? load(id) : fetch(id, :force => options[:force])
      end

      def normalize_source(id, owner, options)
        format = (options[:format] || :text).to_sym
        raise "Unsupported remote data format: #{format}" unless FORMATS.include?(format)
        urls = normalize_urls(options[:urls] || options[:url], options[:headers])
        cache_path = safe_data_path(options[:cache_path] || default_cache_path(id), false)
        local_path = options[:local_path].to_s.strip
        local_path = local_path.empty? ? nil : safe_data_path(local_path, false)
        {
          :id => id,
          :owner => owner,
          :format => format,
          :urls => urls,
          :cache_path => cache_path,
          :local_path => local_path,
          :timeout => positive_integer(options[:timeout], DEFAULT_TIMEOUT),
          :retries => nonnegative_integer(options[:retries], DEFAULT_RETRIES),
          :redirect_limit => nonnegative_integer(options[:redirect_limit], DEFAULT_REDIRECT_LIMIT),
          :max_bytes => positive_integer(options[:max_bytes], DEFAULT_MAX_BYTES),
          :ttl => nonnegative_integer(options[:ttl], 0),
          :allow_empty => !!options[:allow_empty],
          :validator => options[:validator]
        }
      end

      def normalize_urls(value, shared_headers = nil)
        entries = value.is_a?(Array) ? value : (value.nil? ? [] : [value])
        entries.map.with_index do |entry, index|
          row = entry.is_a?(Hash) ? entry : { :url => entry }
          url = (row[:url] || row["url"]).to_s.strip
          next nil if url.empty?
          validate_remote_url!(url)
          headers = normalize_headers(shared_headers || {}).merge(normalize_headers(row[:headers] || row["headers"] || {}))
          {
            :url => url,
            :headers => headers,
            :label => (row[:label] || row["label"] || "source #{index + 1}").to_s
          }
        end.compact
      end

      def public_source(source)
        {
          :id => source[:id],
          :owner => source[:owner],
          :format => source[:format],
          :url_labels => source[:urls].map { |entry| entry[:label].to_s },
          :cache_path => display_path(source[:cache_path]),
          :local_path => source[:local_path] ? display_path(source[:local_path]) : nil,
          :timeout => source[:timeout],
          :retries => source[:retries],
          :redirect_limit => source[:redirect_limit],
          :max_bytes => source[:max_bytes],
          :ttl => source[:ttl]
        }
      end

      def source_config!(id)
        key = normalize_id(id)
        source = key && @sources[key]
        raise "Remote data source is not registered: #{safe_id(id)}" unless source
        source
      end

      def fetch_remote(source, options)
        force = !!options[:force]
        prior = read_cache_record(source)
        error_code = :remote_unavailable
        error_message = "No remote source returned valid data."
        total_attempts = 0
        source[:urls].each do |remote|
          headers = normalize_headers(default_headers).merge(remote[:headers])
          unless force
            metadata = prior && prior[:metadata]
            if metadata && metadata["url_label"].to_s == remote[:label].to_s
              headers["if-none-match"] = metadata["etag"].to_s unless metadata["etag"].to_s.empty?
              headers["if-modified-since"] = metadata["last_modified"].to_s unless metadata["last_modified"].to_s.empty?
            end
          end
          response = perform_request(remote[:url], headers, source, force)
          total_attempts += response[:attempts].to_i
          status = response[:status].to_i
          if status == 304 && prior
            cached = result_from_record(source, prior, :not_modified, nil, "", true, status, total_attempts, remote[:label])
            return cached if cached
          end
          if status == 200
            body = response[:body].to_s
            parsed = parse_and_validate(source, body)
            if parsed[:ok]
              fetched_at = current_time
              metadata = {
                "source_id" => source[:id].to_s,
                "format" => source[:format].to_s,
                "fetched_at" => fetched_at,
                "etag" => response[:headers]["etag"].to_s,
                "last_modified" => response[:headers]["last-modified"].to_s,
                "server_time" => parse_http_time(response[:headers]["date"]),
                "url_label" => remote[:label].to_s
              }
              write_cache_record(source, body, metadata)
              log_info("Remote data refreshed id=#{source[:id]} source=#{remote[:label]} bytes=#{body.bytesize}")
              return Result.new(
                :ok => true, :value => parsed[:value], :body => body,
                :source => :remote, :status => :fresh, :fetched_at => fetched_at,
                :loaded_at => current_time, :http_status => status,
                :attempts => total_attempts, :source_id => source[:id],
                :url_label => remote[:label], :remote_confirmed => true,
                :server_time => metadata["server_time"]
              )
            end
            error_code = parsed[:code]
            error_message = parsed[:message]
          else
            error_code = response[:error_code] || :http_error
            error_message = response[:error_message].to_s
            error_message = "HTTP #{status}" if error_message.empty? && status > 0
          end
        end
        fallback_result(source, error_code, error_message, total_attempts)
      end

      def fallback_result(source, error_code, error_message, attempts = 0)
        cached = cache_result(source, :fallback, error_code, error_message, attempts)
        if cached
          log_warning("Remote data fallback id=#{source[:id]} source=cache reason=#{error_code}") if error_code
          return cached
        end
        local = local_result(source, :fallback, error_code, error_message, attempts)
        if local
          log_warning("Remote data fallback id=#{source[:id]} source=local reason=#{error_code}") if error_code
          return local
        end
        failed_result(source[:id], error_code || :unavailable, error_message.to_s.empty? ? "No valid remote, cached, or local data is available." : error_message, attempts)
      end

      def cache_result(source, status = :cached, error_code = nil, error_message = "", attempts = 0)
        record = read_cache_record(source)
        return nil unless record
        result_from_record(source, record, status, error_code, error_message, false, 0, attempts, record[:metadata]["url_label"])
      end

      def result_from_record(source, record, status, error_code, error_message, remote_confirmed, http_status, attempts, label)
        parsed = parse_and_validate(source, record[:body])
        return nil unless parsed[:ok]
        fetched_at = record[:metadata]["fetched_at"].to_i
        age = fetched_at > 0 ? [current_time - fetched_at, 0].max : 0
        stale = source[:ttl].to_i > 0 && (fetched_at <= 0 || age > source[:ttl].to_i)
        Result.new(
          :ok => true, :value => parsed[:value], :body => record[:body],
          :source => :cache, :status => status, :fetched_at => fetched_at,
          :loaded_at => current_time, :cache_age => age, :stale => stale,
          :http_status => http_status, :attempts => attempts,
          :error_code => error_code, :error_message => sanitize_error(error_message),
          :source_id => source[:id], :url_label => label,
          :remote_confirmed => remote_confirmed,
          :server_time => record[:metadata]["server_time"].to_i
        )
      rescue Exception => e
        log_warning("Remote data cache rejected id=#{source[:id]} reason=#{e.class}")
        nil
      end

      def local_result(source, status = :local, error_code = nil, error_message = "", attempts = 0)
        path = source[:local_path]
        return nil unless path && File.file?(path)
        body = read_limited_file(path, source[:max_bytes])
        parsed = parse_and_validate(source, body)
        return nil unless parsed[:ok]
        Result.new(
          :ok => true, :value => parsed[:value], :body => body,
          :source => :local, :status => status, :fetched_at => (File.mtime(path).to_i rescue 0),
          :loaded_at => current_time, :attempts => attempts,
          :error_code => error_code, :error_message => sanitize_error(error_message),
          :source_id => source[:id]
        )
      rescue Exception => e
        log_warning("Remote data local file rejected id=#{source[:id]} file=#{display_path(path)} reason=#{e.class}")
        nil
      end

      def parse_and_validate(source, body)
        text = body.to_s.sub("\xEF\xBB\xBF", "")
        return { :ok => false, :code => :empty_response, :message => "The response was empty." } if text.empty? && !source[:allow_empty]
        return { :ok => false, :code => :response_too_large, :message => "The response exceeded the configured size limit." } if text.bytesize > source[:max_bytes]
        value = source[:format] == :json ? parse_json(text) : text
        validation = validate_value(source, value)
        return validation unless validation[:ok]
        { :ok => true, :value => value }
      rescue Exception => e
        { :ok => false, :code => :parse_error, :message => sanitize_error(e.message) }
      end

      def validate_value(source, value)
        validator = source[:validator]
        return { :ok => true } unless validator.respond_to?(:call)
        result = validator.call(value)
        return { :ok => true } if result == true
        if result.respond_to?(:ok?)
          return { :ok => true } if result.ok?
          message = result.respond_to?(:message) ? result.message : "Source validation failed."
          return { :ok => false, :code => :validation_failed, :message => sanitize_error(message) }
        end
        message = result.is_a?(String) ? result : "Source validation failed."
        { :ok => false, :code => :validation_failed, :message => sanitize_error(message) }
      rescue Exception => e
        { :ok => false, :code => :validator_error, :message => sanitize_error(e.message) }
      end

      def perform_request(url, headers, source, force)
        original = force ? cache_busted_url(url) : url.to_s
        attempts = 0
        last = nil
        (source[:retries].to_i + 1).times do
          current = original
          request_headers = headers.dup
          redirects = 0
          loop do
            attempts += 1
            response = request_once(current, request_headers, source)
            response[:attempts] = attempts
            status = response[:status].to_i
            if REDIRECT_CODES.include?(status)
              location = response[:headers]["location"].to_s
              return response.merge(:error_code => :invalid_redirect, :error_message => "The server returned an empty redirect.") if location.empty?
              redirects += 1
              return response.merge(:error_code => :redirect_limit, :error_message => "The redirect limit was exceeded.") if redirects > source[:redirect_limit]
              next_url = join_url(current, location)
              return response.merge(:error_code => :insecure_redirect, :error_message => "An insecure redirect was refused.") if https_url?(current) && !https_url?(next_url)
              validate_remote_url!(next_url)
              request_headers = redirect_headers(request_headers, current, next_url)
              current = next_url
              next
            end
            last = response
            break
          end
          break unless retryable_response?(last)
        end
        (last || { :status => 0, :body => "", :headers => {}, :error_code => :network_error, :error_message => "No network transport is available." }).merge(:attempts => attempts)
      rescue Exception => e
        { :status => 0, :body => "", :headers => {}, :attempts => attempts, :error_code => :network_error, :error_message => sanitize_error(e.message) }
      end

      def request_once(url, headers, source)
        if @transport_override.respond_to?(:call)
          return normalize_response(@transport_override.call(url, headers.dup, {
            :timeout => source[:timeout], :max_bytes => source[:max_bytes]
          }))
        end
        if defined?(HTTPLite)
          response = HTTPLite.get(url, headers) rescue nil
          normalized = normalize_response(response) if response.is_a?(Hash)
          return normalized if normalized && normalized[:status].to_i > 0
        end
        network_response = request_with_net_http(url, headers, source[:timeout], source[:max_bytes])
        return network_response if network_response && network_response[:status].to_i > 0
        if custom_headers_empty?(headers) && defined?(pbDownloadToString)
          body = pbDownloadToString(url) rescue ""
          return normalize_response(:status => 200, :body => body, :headers => {}) unless body.to_s.empty?
        end
        network_response || { :status => 0, :body => "", :headers => {}, :error_code => :network_unavailable, :error_message => "No compatible network transport is available." }
      rescue Exception => e
        { :status => 0, :body => "", :headers => {}, :error_code => :network_error, :error_message => sanitize_error(e.message) }
      end

      def request_with_net_http(url, headers, timeout, max_bytes)
        return nil unless defined?(Net::HTTP) && defined?(URI)
        uri = URI.parse(url.to_s)
        request = Net::HTTP::Get.new(uri)
        headers.each { |key, value| request[key.to_s] = value.to_s }
        response = Net::HTTP.start(
          uri.host, uri.port, :use_ssl => uri.scheme == "https",
          :open_timeout => timeout, :read_timeout => timeout
        ) { |http| http.request(request) }
        body = response.body.to_s
        raise "Response exceeded #{max_bytes} bytes." if body.bytesize > max_bytes.to_i
        normalize_response(:status => response.code.to_i, :body => body, :headers => response.each_header.to_h)
      rescue Exception => e
        { :status => 0, :body => "", :headers => {}, :error_code => :network_error, :error_message => sanitize_error(e.message) }
      end

      def normalize_response(response)
        row = response.is_a?(Hash) ? response : {}
        headers = row[:headers] || row["headers"] || row[:header] || row["header"] || {}
        direct_location = row[:location] || row["location"] || row[:Location] || row["Location"]
        normalized_headers = normalize_headers(headers)
        normalized_headers["location"] = direct_location.to_s unless direct_location.to_s.empty?
        {
          :status => (row[:status] || row["status"] || row[:code] || row["code"]).to_i,
          :body => (row[:body] || row["body"] || "").to_s,
          :headers => normalized_headers,
          :error_code => row[:error_code] || row["error_code"],
          :error_message => sanitize_error(row[:error_message] || row["error_message"])
        }
      end

      def read_cache_record(source)
        path = source[:cache_path]
        return nil unless path && File.file?(path)
        # Version 2 stores response text as hexadecimal, so its cache envelope
        # can be a little over twice the original response size.
        raw = read_limited_file(path, source[:max_bytes] * 2 + 500_000)
        envelope = parse_json(raw)
        return nil unless envelope.is_a?(Hash)
        version = envelope["remote_data_cache"].to_i
        return nil unless [1, 2].include?(version)
        if version == 2
          body = hex_decode(envelope["body_hex"])
          metadata = decode_cache_metadata(envelope["metadata"])
        else
          body = envelope["body"].to_s
          metadata = envelope["metadata"].is_a?(Hash) ? envelope["metadata"] : {}
        end
        return nil if body.bytesize > source[:max_bytes]
        { :body => body, :metadata => metadata }
      rescue Exception => e
        log_warning("Remote data cache could not be read id=#{source[:id]} file=#{display_path(path)} reason=#{e.class}")
        nil
      end

      def write_cache_record(source, body, metadata)
        path = source[:cache_path]
        ensure_directory(File.dirname(path))
        # The engine's lightweight JSON.generate does not escape quotes or
        # newlines. Encode remote strings so ETags and JSON response bodies
        # cannot corrupt the cache envelope.
        envelope = {
          "remote_data_cache" => 2,
          "metadata" => encode_cache_metadata(metadata),
          "body_hex" => hex_encode(body.to_s)
        }
        payload = JSON.generate(envelope)
        temp = "#{path}.tmp"
        backup = "#{path}.bak"
        File.open(temp, "wb") { |file| file.write(payload) }
        verified = parse_json(File.read(temp))
        raise "Remote data cache verification failed." unless verified.is_a?(Hash) && verified["remote_data_cache"].to_i == 2
        verified_body_hex = verified["body_hex"].to_s.downcase
        raise "Remote data cache body verification failed." unless verified_body_hex == hex_encode(body.to_s)
        File.delete(backup) if File.file?(backup)
        File.rename(path, backup) if File.file?(path)
        File.rename(temp, path)
        File.delete(backup) if File.file?(backup)
        true
      rescue Exception => e
        File.delete(temp) rescue nil if defined?(temp) && temp
        if defined?(backup) && backup && File.file?(backup) && !File.file?(path)
          File.rename(backup, path) rescue nil
        end
        log_exception("Remote data cache write failed id=#{source[:id]}", e)
        false
      end

      def encode_cache_metadata(metadata)
        result = {}
        (metadata.is_a?(Hash) ? metadata : {}).each do |key, value|
          name = key.to_s
          if value.is_a?(Numeric)
            result[name] = { "type" => "number", "value" => value }
          elsif value == true || value == false
            result[name] = { "type" => "boolean", "value" => value }
          else
            result[name] = { "type" => "string", "value_hex" => hex_encode(value.to_s) }
          end
        end
        result
      end

      def decode_cache_metadata(metadata)
        return {} unless metadata.is_a?(Hash)
        result = {}
        metadata.each do |key, row|
          next unless row.is_a?(Hash)
          case row["type"].to_s
          when "number", "boolean"
            result[key.to_s] = row["value"]
          when "string"
            result[key.to_s] = hex_decode(row["value_hex"])
          end
        end
        result
      end

      def hex_encode(value)
        value.to_s.unpack("H*")[0].to_s
      end

      def hex_decode(value)
        text = value.to_s
        raise "Invalid encoded cache value." if text.length.odd? || text !~ /\A[0-9a-f]*\z/i
        [text].pack("H*")
      end

      def parse_json(raw)
        raise "JSON parser is not available." unless defined?(JSON)
        text = strip_utf8_bom(raw)
        begin
          stringify_keys(JSON.parse(text))
        rescue NameError => e
          missing_name = e.respond_to?(:name) ? e.name.to_s : ""
          raise unless missing_name == "null" || e.message.to_s =~ /[`'"]null[`'"]/
          stringify_keys(JSON.parse(rewrite_null_literals(text)))
        end
      end

      def strip_utf8_bom(raw)
        text = raw.to_s.dup
        if text.bytesize >= 3 &&
           text.getbyte(0) == 0xEF &&
           text.getbyte(1) == 0xBB &&
           text.getbyte(2) == 0xBF
          text = text.byteslice(3, text.bytesize - 3)
        end
        text
      end

      def rewrite_null_literals(text)
        output = +""
        index = 0
        in_string = false
        escaped = false
        while index < text.length
          char = text[index]
          if in_string
            output << char
            if escaped
              escaped = false
            elsif char == "\\"
              escaped = true
            elsif char == "\""
              in_string = false
            end
            index += 1
            next
          end
          if char == "\""
            in_string = true
            output << char
            index += 1
            next
          end
          if text[index, 4] == "null" && json_boundary?(text[index - 1]) && json_boundary?(text[index + 4])
            output << "nil"
            index += 4
            next
          end
          output << char
          index += 1
        end
        output
      end

      def json_boundary?(char)
        char.nil? || char !~ /[A-Za-z0-9_]/
      end

      def stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, child), memo| memo[key.to_s] = stringify_keys(child) }
        when Array
          value.map { |child| stringify_keys(child) }
        else
          value
        end
      end

      def default_headers
        {
          "Cache-Control" => "no-cache",
          "Pragma" => "no-cache",
          "Proxy-Connection" => "Close",
          "User-Agent" => USER_AGENT
        }
      end

      def normalize_headers(headers)
        result = {}
        headers.to_h.each { |key, value| result[key.to_s.downcase] = value.to_s }
        result
      rescue
        {}
      end

      def custom_headers_empty?(headers)
        custom = normalize_headers(headers)
        default_headers.keys.each { |key| custom.delete(key.downcase) }
        custom.empty?
      end

      def retryable_response?(response)
        return true if response.nil?
        status = response[:status].to_i
        status <= 0 || RETRYABLE_CODES.include?(status)
      end

      def validate_remote_url!(url)
        value = url.to_s.strip
        raise "Remote URL is empty." if value.empty?
        raise "Only HTTPS remote data URLs are allowed." unless value =~ /\Ahttps:\/\//i
        true
      end

      def https_url?(url)
        url.to_s =~ /\Ahttps:\/\//i
      end

      def join_url(base, location)
        return URI.join(base.to_s, location.to_s).to_s if defined?(URI)
        return location.to_s if location.to_s =~ /\Ahttps?:\/\//i
        location.to_s
      rescue
        location.to_s
      end

      def redirect_headers(headers, from_url, to_url)
        result = headers.dup
        return result if same_origin?(from_url, to_url)
        ["authorization", "proxy-authorization", "cookie"].each { |key| result.delete(key) }
        result.delete("if-none-match")
        result.delete("if-modified-since")
        result
      end

      def same_origin?(first, second)
        return false unless defined?(URI)
        left = URI.parse(first.to_s)
        right = URI.parse(second.to_s)
        left.scheme.to_s.downcase == right.scheme.to_s.downcase &&
          left.host.to_s.downcase == right.host.to_s.downcase &&
          effective_port(left) == effective_port(right)
      rescue
        false
      end

      def effective_port(uri)
        return uri.port.to_i if uri.port
        uri.scheme.to_s.downcase == "https" ? 443 : 80
      end

      def cache_busted_url(url)
        joiner = url.to_s.include?("?") ? "&" : "?"
        "#{url}#{joiner}rld_remote=#{current_time}_#{rand(100000)}"
      end

      def safe_data_path(path, must_exist)
        if defined?(Reloaded::FileActions)
          return Reloaded::FileActions.resolve(path, :must_exist => must_exist)
        end
        expanded = File.expand_path(path.to_s, GAME_ROOT)
        base = GAME_ROOT.to_s.gsub("\\", "/").downcase
        value = expanded.to_s.gsub("\\", "/").downcase
        raise "Remote data path is outside the game folder." unless value == base || value.start_with?(base + "/")
        expanded
      end

      def default_cache_path(id)
        File.join(CACHE_ROOT, "#{safe_key(id)}.json")
      end

      def read_limited_file(path, max_bytes)
        size = File.size(path).to_i
        raise "File exceeded the configured size limit." if size > max_bytes.to_i
        File.open(path, "rb") { |file| file.read }
      end

      def ensure_directory(path)
        return if Dir.exist?(path)
        parent = File.dirname(path)
        ensure_directory(parent) unless parent == path || Dir.exist?(parent)
        Dir.mkdir(path)
      end

      def remote_supported?
        !defined?(Reloaded::Platform) || Reloaded::Platform.supports?(:remote_data)
      rescue
        false
      end

      def failed_result(id, code, message, attempts = 0)
        Result.new(
          :ok => false, :source => :none, :status => :failed,
          :loaded_at => current_time, :attempts => attempts,
          :error_code => code || :unavailable,
          :error_message => sanitize_error(message), :source_id => normalize_id(id)
        )
      end

      def normalize_id(value)
        text = value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "")
        text.empty? ? nil : text.to_sym
      end

      def safe_key(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_-]+/, "_").gsub(/\A_+|_+\z/, "")
      end

      def safe_id(value)
        normalize_id(value) || :unknown
      end

      def positive_integer(value, fallback)
        number = value.nil? ? fallback : value.to_i
        number > 0 ? number : fallback
      end

      def nonnegative_integer(value, fallback)
        number = value.nil? ? fallback : value.to_i
        number >= 0 ? number : fallback
      end

      def current_time
        Time.now.to_i
      rescue
        0
      end

      def parse_http_time(value)
        text = value.to_s.strip
        return 0 if text.empty?
        return Time.httpdate(text).to_i if Time.respond_to?(:httpdate)
        Time.parse(text).to_i
      rescue
        0
      end

      def display_path(path)
        return Reloaded::FileActions.display_path(path) if defined?(Reloaded::FileActions)
        File.basename(path.to_s)
      rescue
        File.basename(path.to_s)
      end

      def sanitize_error(value)
        text = value.to_s.gsub(/https:\/\/[^\s?]+\?[^\s]+/i) { |url| url.split("?").first }
        return Reloaded::Log.sanitize(text) if defined?(Reloaded::Log) && Reloaded::Log.respond_to?(:sanitize)
        text
      rescue
        value.to_s
      end

      def log_info(message)
        Reloaded::Log.info(message, :framework) if defined?(Reloaded::Log)
      rescue
      end

      def log_warning(message)
        Reloaded::Log.warning(message, :framework) if defined?(Reloaded::Log)
      rescue
      end

      def log_exception(message, error)
        Reloaded::Log.exception(message, error, channel: :framework) if defined?(Reloaded::Log)
      rescue
      end
    end
  end
end
