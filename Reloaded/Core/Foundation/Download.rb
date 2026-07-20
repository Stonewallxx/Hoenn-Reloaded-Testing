#======================================================
# Reloaded Download API
# Author: Stonewall
#======================================================
# Safe large-file downloads for Reloaded runtime systems and mods.
# Writes to a same-directory .part file, validates the completed payload, and
# only then promotes it to the requested destination.
#======================================================

begin
  require "net/http"
  require "uri"
  require "thread"
  require "time"
rescue Exception
end

begin
  require "digest/sha2"
rescue Exception
  begin
    require "digest"
  rescue Exception
  end
end

begin
  require "json"
rescue Exception
end

module Reloaded
  module Download
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    DEFAULT_OPEN_TIMEOUT = 15
    DEFAULT_READ_TIMEOUT = 45
    DEFAULT_REDIRECT_LIMIT = 6
    DEFAULT_RETRIES = 2
    DEFAULT_RETRY_DELAY = 1.0
    DEFAULT_MAX_BYTES = 50 * 1024 * 1024 * 1024
    DEFAULT_MIN_BYTES = 1
    DEFAULT_CONNECTIONS = 3
    MAX_CONNECTIONS = 3
    MULTIPART_MIN_BYTES = 24 * 1024 * 1024
    STREAM_BUFFER_BYTES = 1024 * 1024
    DISK_SPACE_MARGIN = 64 * 1024 * 1024
    PART_META_VERSION = 1
    USER_AGENT = "Hoenn Reloaded Download"
    REDIRECT_CODES = [301, 302, 303, 307, 308].freeze
    RETRYABLE_CODES = [:network_error, :timeout, :incomplete_download,
                       :transport_failed, :checksum_mismatch,
                       :http_server_error, :http_rate_limited,
                       :resume_rejected].freeze
    SENSITIVE_HEADERS = ["authorization", "proxy-authorization", "cookie"].freeze
    MAX_ERROR_TEXT = 700

    class Result
      attr_reader :status, :error_code, :error_message, :url, :final_url,
                  :destination, :bytes, :expected_bytes, :sha256, :duration,
                  :attempts, :transport, :http_status, :headers

      def initialize(values = {})
        @success = !!values[:success]
        @status = (values[:status] || (@success ? :downloaded : :failed)).to_sym
        @error_code = values[:error_code] && values[:error_code].to_sym
        @error_message = values[:error_message].to_s
        @url = values[:url].to_s
        @final_url = values[:final_url].to_s
        @destination = values[:destination].to_s
        @bytes = values[:bytes].to_i
        @expected_bytes = values[:expected_bytes].to_i
        @sha256 = values[:sha256].to_s
        @duration = values[:duration].to_f
        @attempts = values[:attempts].to_i
        @transport = values[:transport] && values[:transport].to_sym
        @http_status = values[:http_status].to_i
        @headers = values[:headers].is_a?(Hash) ? values[:headers].dup : {}
      end

      def success?
        @success
      end

      alias ok? success?
    end

    class Failure < StandardError
      attr_reader :code, :http_status, :retry_after

      def initialize(code, message, http_status = 0, retry_after = 0)
        @code = code.to_sym
        @http_status = http_status.to_i
        @retry_after = retry_after.to_f
        super(message.to_s)
      end
    end

    @connection_mutex = defined?(Mutex) ? Mutex.new : nil
    @connection_condition = defined?(ConditionVariable) ? ConditionVariable.new : nil
    @connections_in_use = 0

    class << self
      def available?
        return false unless defined?(Reloaded::Platform)
        return false unless Reloaded::Platform.supports?(:downloads)
        !!@transport_override || net_http_available? || !powershell_path.nil?
      rescue
        false
      end

      def fetch(url, destination, options = {})
        started = Time.now
        opts = normalize_options(options)
        source_url = validate_url!(url)
        target = validate_destination!(destination, opts)
        part = "#{target}.part"
        ensure_download_space!(part, opts)
        attempts = 0
        last_error = nil
        metadata = nil
        report(opts[:task], 0.0, download_stage(opts), opts)
        transports(opts).each do |transport|
          (opts[:retries] + 1).times do |retry_index|
            attempts += 1
            checkpoint!(opts[:task])
            wait_for_retry(last_error, retry_index, opts) if retry_index > 0
            delete_partial(part) unless resumable_part?(part, opts)
            stage = download_stage(opts)
            stage += " (retry #{retry_index})" if retry_index > 0
            report(opts[:task], 0.0, stage, opts)
            begin
              metadata = perform_transport(transport, source_url, part, opts)
              verified = verify_download!(part, metadata, opts)
              promote_part!(part, target)
              delete_file(part_meta_path(part))
              report(opts[:task], 1.0, complete_stage(opts), opts)
              result = Result.new(
                :success => true,
                :status => :downloaded,
                :url => display_url(source_url),
                :final_url => display_url(metadata[:final_url] || source_url),
                :destination => display_path(target),
                :bytes => verified[:bytes],
                :expected_bytes => verified[:expected_bytes],
                :sha256 => verified[:sha256],
                :duration => elapsed(started),
                :attempts => attempts,
                :transport => transport,
                :http_status => metadata[:http_status],
                :headers => metadata[:headers]
              )
              log_info("Download complete destination=#{result.destination} bytes=#{result.bytes} transport=#{result.transport} attempts=#{attempts}")
              return result
            rescue Failure => e
              last_error = e
              delete_partial(part) unless preserve_partial?(part, opts, e)
              break if terminal_failure?(e) || !retryable_failure?(e)
            end
          end
          break if last_error && terminal_failure?(last_error)
        end
        raise(last_error || Failure.new(:transport_unavailable, "No download transport is available."))
      rescue Exception => e
        if defined?(part) && part
          delete_partial(part) unless defined?(opts) && preserve_partial?(part, opts, e)
        end
        raise if cancelled_exception?(e)
        result = failed_result(e, url, destination, started, attempts || 0)
        log_error("Download failed destination=#{result.destination} code=#{result.error_code} reason=#{result.error_message} attempts=#{result.attempts}")
        result
      end

      alias download fetch

      def fetch!(url, destination, options = {})
        result = fetch(url, destination, options)
        raise Failure.new(result.error_code || :download_failed, result.error_message, result.http_status) unless result.success?
        result
      end

      alias download! fetch!

      def start(url, destination, options = {})
        raise "Background tasks are unavailable." unless defined?(Reloaded::Task)
        opts = options.is_a?(Hash) ? options.dup : {}
        task_options = opts.delete(:task_options)
        task_options = task_options.is_a?(Hash) ? task_options.dup : {}
        task_options[:owner] ||= :download
        task_options[:duplicate] ||= :reuse
        key = opts.delete(:key) || "download_#{safe_key(File.basename(destination.to_s))}"
        Reloaded::Task.start(key, task_options) do |task|
          result = fetch(url, destination, opts.merge(:task => task))
          task.fail!(result.error_message, result.error_code || :download_failed) unless result.success?
          result
        end
      end

      # Internal release-test seam. Production callers use the built-in
      # platform transports.
      def transport_override=(callback)
        @transport_override = callback
      end

      private

      def normalize_options(options)
        source = options.is_a?(Hash) ? options : {}
        opts = {}
        source.each { |key, value| opts[(key.to_sym rescue key)] = value }
        opts[:headers] = normalize_headers(opts[:headers])
        opts[:headers]["user-agent"] ||= USER_AGENT
        opts[:headers]["cache-control"] ||= "no-cache"
        opts[:headers]["pragma"] ||= "no-cache"
        opts[:headers]["accept-encoding"] ||= "identity"
        opts[:open_timeout] = positive_integer(opts[:open_timeout], DEFAULT_OPEN_TIMEOUT)
        opts[:read_timeout] = positive_integer(opts[:read_timeout] || opts[:timeout], DEFAULT_READ_TIMEOUT)
        opts[:redirect_limit] = nonnegative_integer(opts[:redirect_limit], DEFAULT_REDIRECT_LIMIT)
        opts[:retries] = nonnegative_integer(opts[:retries], DEFAULT_RETRIES)
        opts[:retry_delay] = positive_number(opts[:retry_delay], DEFAULT_RETRY_DELAY)
        opts[:min_bytes] = nonnegative_integer(opts[:min_bytes], DEFAULT_MIN_BYTES)
        opts[:max_bytes] = positive_integer(opts[:max_bytes], DEFAULT_MAX_BYTES)
        opts[:expected_bytes] = nonnegative_integer(opts[:expected_bytes] || opts[:size], 0)
        opts[:sha256] = normalize_sha256(opts[:sha256] || opts[:checksum])
        opts[:resume] = !!opts[:resume]
        opts[:disk_space_check] = opts.key?(:disk_space_check) ? !!opts[:disk_space_check] : true
        opts[:connections] = positive_integer(opts[:connections], DEFAULT_CONNECTIONS)
        opts[:connections] = [opts[:connections], MAX_CONNECTIONS].min
        opts[:label] = opts[:label].to_s.strip
        opts[:allowed_roots] = allowed_roots
        opts[:progress_range] = normalize_progress_range(opts[:progress_range])
        opts
      end

      def validate_url!(url)
        value = url.to_s.strip
        raise_failure(:invalid_url, "Download URL is empty.") if value.empty?
        raise_failure(:invalid_url, "Only HTTPS download URLs are allowed.") unless value =~ /\Ahttps:\/\//i
        uri = URI.parse(value) if defined?(URI)
        raise_failure(:invalid_url, "Download URL has no host.") if uri && uri.host.to_s.empty?
        raise_failure(:invalid_url, "Download URLs cannot contain embedded credentials.") if uri && !uri.userinfo.to_s.empty?
        value
      rescue Failure
        raise
      rescue Exception
        raise_failure(:invalid_url, "Download URL is invalid.")
      end

      def validate_destination!(destination, opts)
        path = File.expand_path(destination.to_s)
        raise_failure(:invalid_destination, "Download destination is empty.") if destination.to_s.strip.empty?
        valid = opts[:allowed_roots].any? { |root| under_path?(path, root) }
        raise_failure(:destination_outside_allowed_roots, "Download destination is outside the allowed folders.") unless valid
        raise_failure(:destination_is_directory, "Download destination is a folder.") if File.directory?(path)
        ensure_directory(File.dirname(path))
        path
      end

      def allowed_roots
        roots = [GAME_ROOT]
        roots << Reloaded::Platform.temporary_directory if defined?(Reloaded::Platform)
        roots.map { |root| File.expand_path(root.to_s) }.uniq
      end

      def under_path?(path, root)
        target = canonical_path(path)
        base = canonical_path(root)
        target == base || target.start_with?(base + "/")
      end

      def canonical_path(path)
        expanded = File.expand_path(path.to_s)
        missing = []
        cursor = expanded
        until File.exist?(cursor)
          parent = File.dirname(cursor)
          break if parent == cursor
          missing.unshift(File.basename(cursor))
          cursor = parent
        end
        base = File.exist?(cursor) ? File.realpath(cursor) : cursor
        value = (missing.empty? ? base : File.expand_path(File.join(base, *missing))).gsub("\\", "/").sub(/\/+\z/, "")
        case_insensitive_paths? ? value.downcase : value
      rescue
        value = File.expand_path(path.to_s).gsub("\\", "/").sub(/\/+\z/, "")
        case_insensitive_paths? ? value.downcase : value
      end

      def case_insensitive_paths?
        return true unless defined?(Reloaded::Platform)
        [:windows, :proton].include?(Reloaded::Platform.id)
      rescue
        true
      end

      def transports(opts)
        raise_failure(:unsupported_platform, "Downloads are unavailable on this platform.") unless platform_supported?
        return [:override] if @transport_override
        result = []
        result << :net_http if net_http_available?
        result << :powershell if powershell_path
        raise_failure(:transport_unavailable, "No download transport is available.") if result.empty?
        result
      end

      def platform_supported?
        !defined?(Reloaded::Platform) || Reloaded::Platform.supports?(:downloads)
      rescue
        false
      end

      def net_http_available?
        defined?(Net::HTTP) && defined?(URI)
      rescue
        false
      end

      def perform_transport(transport, url, part, opts)
        case transport
        when :override
          metadata = @transport_override.call(url, part, opts, opts[:task])
          metadata.is_a?(Hash) ? metadata : {}
        when :net_http
          stream_with_net_http(url, part, opts)
        when :powershell
          with_connection_slot(opts[:task]) { stream_with_powershell(url, part, opts) }
        else
          raise_failure(:transport_unavailable, "Unknown download transport.")
        end
      rescue Failure
        raise
      rescue Exception => e
        raise if cancelled_exception?(e)
        raise_failure(:transport_failed, sanitize_error(e.message, "Download transport failed."))
      end

      def stream_with_net_http(url, part, opts)
        if multipart_candidate?(part, opts)
          begin
            metadata = stream_multipart_with_net_http(url, part, opts)
            return metadata if metadata
          rescue Failure => e
            raise unless e.code == :range_unsupported
            delete_partial(part)
            log_info("Parallel download unavailable; using one connection.")
          end
        end
        stream_single_with_net_http(url, part, opts)
      end

      def stream_single_with_net_http(url, part, opts)
        current = url
        headers = opts[:headers].dup
        redirects = 0
        loop do
          checkpoint!(opts[:task])
          uri = URI.parse(current)
          request_path = uri.request_uri.to_s
          request_path = "/" if request_path.empty?
          request = Net::HTTP::Get.new(request_path)
          headers.each { |key, value| request[key] = value }
          resume_bytes = resumable_part?(part, opts) ? File.size(part).to_i : 0
          request["range"] = "bytes=#{resume_bytes}-" if resume_bytes > 0
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = opts[:open_timeout] if http.respond_to?(:open_timeout=)
          http.read_timeout = opts[:read_timeout] if http.respond_to?(:read_timeout=)
          metadata = nil
          with_connection_slot(opts[:task]) do
            http.start do |connection|
              connection.request(request) do |response|
              status = response.code.to_i
              if REDIRECT_CODES.include?(status)
                location = response["location"].to_s
                raise_failure(:redirect_missing, "Download redirect did not include a location.", status) if location.empty?
                redirects += 1
                raise_failure(:too_many_redirects, "Download exceeded the redirect limit.", status) if redirects > opts[:redirect_limit]
                next_url = join_url(current, location)
                validate_url!(next_url)
                headers = redirect_headers(headers, current, next_url)
                metadata = { :redirect => next_url }
                next
              end
              if status == 416 && resume_bytes > 0
                delete_file(part)
                raise_failure(:resume_rejected, "The server rejected the partial download.", status)
              end
              unless status == 200 || (status == 206 && resume_bytes > 0)
                raise_http_failure(response)
              end
              partial = status == 206 && resume_bytes > 0
              expected = response["content-length"].to_i
              total = partial ? response_total_bytes(response, resume_bytes, expected) : expected
              total = opts[:expected_bytes] if total <= 0 && opts[:expected_bytes].to_i > 0
              validate_announced_size!(total, opts)
              digest = sha256_digest
              update_digest_from_file(digest, part) if partial && digest
              bytes = partial ? resume_bytes : 0
              File.open(part, partial ? "ab" : "wb") do |file|
                response.read_body do |chunk|
                  checkpoint!(opts[:task])
                  data = chunk.to_s
                  bytes += data.bytesize
                  raise_failure(:file_too_large, "Download exceeded the configured size limit.", status) if bytes > opts[:max_bytes]
                  file.write(data)
                  digest.update(data) if digest
                  report_bytes(opts[:task], bytes, total, opts)
                end
                file.flush rescue nil
              end
              metadata = {
                :final_url => current,
                :http_status => status,
                :content_length => total,
                :bytes => bytes,
                :sha256 => digest ? digest.hexdigest : "",
                :headers => safe_response_headers(response)
              }
              end
            end
          end
          if metadata && metadata[:redirect]
            current = metadata[:redirect]
            next
          end
          return metadata || {}
        end
      rescue Failure
        raise
      rescue Exception => e
        raise if cancelled_exception?(e)
        code = timeout_exception?(e) ? :timeout : :network_error
        raise_failure(code, sanitize_error(e.message, "Network download failed."))
      end

      def multipart_candidate?(part, opts)
        return false unless defined?(Thread) && defined?(Mutex)
        return false if opts[:connections].to_i <= 1
        return false if File.file?(part) && !multipart_part?(part)
        expected = opts[:expected_bytes].to_i
        expected <= 0 || expected >= MULTIPART_MIN_BYTES
      rescue
        false
      end

      def stream_multipart_with_net_http(url, part, opts)
        probe = probe_range_support(url, opts)
        return nil unless probe
        total = probe[:total].to_i
        return nil if total < MULTIPART_MIN_BYTES
        connections = [[opts[:connections].to_i, 1].max, MAX_CONNECTIONS].min
        connections = [connections, total].min
        return nil if connections <= 1
        validate_announced_size!(total, opts)
        ensure_download_space_for_total!(part, total, opts)

        state = load_multipart_state(part, url, total, connections, probe)
        unless state
          delete_partial(part)
          ranges = split_byte_ranges(total, connections).map do |range|
            { :start => range[0], :end => range[1], :received => 0 }
          end
          state = {
            :version => PART_META_VERSION,
            :url_sha256 => text_sha256(url),
            :total => total,
            :etag => probe[:response_headers]["etag"].to_s,
            :last_modified => probe[:response_headers]["last-modified"].to_s,
            :ranges => ranges
          }
          File.open(part, "wb") { |file| file.truncate(total) }
          write_part_meta(part, state)
        end
        ranges = state[:ranges]
        threads = []
        shared = {
          :mutex => Mutex.new,
          :bytes => ranges.inject(0) { |sum, range| sum + range[:received].to_i },
          :error => nil,
          :cancelled => false
        }
        ranges.each do |range|
          next if range[:received].to_i >= range[:end].to_i - range[:start].to_i + 1
          threads << Thread.new do
            begin
              stream_net_http_range(
                probe[:final_url], probe[:headers], range, total, part,
                state, opts, shared
              )
            rescue Exception => e
              shared[:mutex].synchronize do
                shared[:error] ||= e
                shared[:cancelled] = true
              end
            end
          end
        end

        while threads.any? { |thread| thread.alive? }
          checkpoint!(opts[:task])
          error = nil
          bytes = 0
          shared[:mutex].synchronize do
            error = shared[:error]
            bytes = shared[:bytes]
          end
          break if error
          report_bytes(opts[:task], bytes, total, opts)
          write_part_meta(part, snapshot_multipart_state(state, shared))
          sleep(0.05)
        end
        threads.each { |thread| thread.join rescue nil }
        error = nil
        bytes = 0
        shared[:mutex].synchronize do
          error = shared[:error]
          bytes = shared[:bytes]
        end
        raise error if error
        raise_failure(:incomplete_download, "Parallel download did not receive the complete file.") unless bytes == total
        delete_file(part_meta_path(part))
        report_bytes(opts[:task], total, total, opts)
        {
          :final_url => probe[:final_url],
          :http_status => 206,
          :content_length => total,
          :bytes => total,
          :sha256 => file_sha256(part),
          :headers => probe[:response_headers]
        }
      rescue Failure
        raise
      rescue Exception => e
        raise if cancelled_exception?(e)
        code = timeout_exception?(e) ? :timeout : :network_error
        raise_failure(code, sanitize_error(e.message, "Parallel download failed."))
      ensure
        if defined?(shared) && shared
          shared[:mutex].synchronize { shared[:cancelled] = true } rescue nil
        end
        if defined?(threads) && threads
          threads.each do |thread|
            thread.kill if thread.alive? rescue nil
            thread.join rescue nil
          end
        end
        if defined?(state) && state && defined?(part) && File.file?(part) &&
           File.file?(part_meta_path(part))
          write_part_meta(part, snapshot_multipart_state(state, shared)) rescue nil
        end
      end

      def probe_range_support(url, opts)
        current = url
        headers = opts[:headers].dup
        redirects = 0
        loop do
          checkpoint!(opts[:task])
          response_data = net_http_range_request(current, headers, 0, 0, opts) do |response|
            status = response.code.to_i
            if REDIRECT_CODES.include?(status)
              [:redirect, response["location"].to_s, status]
            elsif status == 200 || status == 416
              [:unsupported, nil, status]
            elsif status == 206
              total = validated_content_range(response, 0, 0)
              response.read_body { |_chunk| } rescue nil
              [:supported, total, status, safe_response_headers(response)]
            else
              raise_http_failure(response)
            end
          end
          case response_data[0]
          when :redirect
            location = response_data[1].to_s
            raise_failure(:redirect_missing, "Download redirect did not include a location.", response_data[2]) if location.empty?
            redirects += 1
            raise_failure(:too_many_redirects, "Download exceeded the redirect limit.", response_data[2]) if redirects > opts[:redirect_limit]
            next_url = join_url(current, location)
            validate_url!(next_url)
            headers = redirect_headers(headers, current, next_url)
            current = next_url
          when :supported
            return {
              :final_url => current,
              :headers => headers,
              :total => response_data[1],
              :response_headers => response_data[3] || {}
            }
          else
            return nil
          end
        end
      rescue Failure
        raise
      rescue Exception => e
        raise if cancelled_exception?(e)
        code = timeout_exception?(e) ? :timeout : :network_error
        raise_failure(code, sanitize_error(e.message, "Download range check failed."))
      end

      def stream_net_http_range(url, headers, range, total, path, state, opts, shared)
        current = url
        current_headers = headers.dup
        validator = state[:etag].to_s
        validator = state[:last_modified].to_s if validator.empty?
        current_headers["if-range"] = validator unless validator.empty?
        redirects = 0
        loop do
          raise_failure(:range_unsupported, "Parallel download was cancelled.") if multipart_cancelled?(shared)
          received_before = shared[:mutex].synchronize { range[:received].to_i }
          first_byte = range[:start].to_i + received_before
          last_byte = range[:end].to_i
          return true if first_byte > last_byte
          response_data = net_http_range_request(current, current_headers, first_byte, last_byte, opts) do |response|
            status = response.code.to_i
            if REDIRECT_CODES.include?(status)
              [:redirect, response["location"].to_s, status]
            elsif status == 429 || status >= 500
              raise_http_failure(response)
            elsif status != 206
              [:unsupported, nil, status]
            else
              validated_content_range(response, first_byte, last_byte, total)
              expected = last_byte - first_byte + 1
              bytes = 0
              File.open(path, "r+b") do |file|
                file.seek(first_byte, IO::SEEK_SET)
                response.read_body do |chunk|
                  raise_failure(:range_unsupported, "Parallel download was cancelled.") if multipart_cancelled?(shared)
                  data = chunk.to_s
                  bytes += data.bytesize
                  raise_failure(:range_unsupported, "Server returned too much data for a byte range.", status) if bytes > expected
                  file.write(data)
                  shared[:mutex].synchronize do
                    range[:received] += data.bytesize
                    shared[:bytes] += data.bytesize
                  end
                end
                file.flush rescue nil
              end
              raise_failure(:incomplete_download, "A parallel download segment was incomplete.", status) unless bytes == expected
              [:complete, nil, status]
            end
          end
          case response_data[0]
          when :redirect
            location = response_data[1].to_s
            raise_failure(:redirect_missing, "Download redirect did not include a location.", response_data[2]) if location.empty?
            redirects += 1
            raise_failure(:too_many_redirects, "Download exceeded the redirect limit.", response_data[2]) if redirects > opts[:redirect_limit]
            next_url = join_url(current, location)
            validate_url!(next_url)
            current_headers = redirect_headers(current_headers, current, next_url)
            current = next_url
          when :complete
            return true
          else
            raise_failure(:range_unsupported, "The server did not honor parallel byte ranges.", response_data[2])
          end
        end
      rescue Failure
        raise
      rescue Exception => e
        code = timeout_exception?(e) ? :timeout : :network_error
        raise_failure(code, sanitize_error(e.message, "Parallel download segment failed."))
      end

      def net_http_range_request(url, headers, first_byte, last_byte, opts)
        uri = URI.parse(url)
        request_path = uri.request_uri.to_s
        request_path = "/" if request_path.empty?
        request = Net::HTTP::Get.new(request_path)
        headers.each { |key, value| request[key] = value }
        request["range"] = "bytes=#{first_byte}-#{last_byte}"
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = opts[:open_timeout] if http.respond_to?(:open_timeout=)
        http.read_timeout = opts[:read_timeout] if http.respond_to?(:read_timeout=)
        value = nil
        with_connection_slot(opts[:task]) do
          http.start do |connection|
            connection.request(request) { |response| value = yield(response) }
          end
        end
        value
      end

      def validated_content_range(response, expected_first, expected_last, expected_total = nil)
        value = response["content-range"].to_s
        unless value =~ /\Abytes\s+(\d+)-(\d+)\/(\d+)\z/i
          raise_failure(:range_unsupported, "Server returned an invalid byte range.", response.code.to_i)
        end
        first_byte = Regexp.last_match(1).to_i
        last_byte = Regexp.last_match(2).to_i
        total = Regexp.last_match(3).to_i
        valid = first_byte == expected_first.to_i &&
                last_byte == expected_last.to_i &&
                total > last_byte
        valid &&= total == expected_total.to_i if expected_total
        raise_failure(:range_unsupported, "Server returned the wrong byte range.", response.code.to_i) unless valid
        total
      end

      def split_byte_ranges(total, count)
        ranges = []
        base = total.to_i / count.to_i
        remainder = total.to_i % count.to_i
        first_byte = 0
        count.to_i.times do |index|
          length = base + (index < remainder ? 1 : 0)
          last_byte = first_byte + length - 1
          ranges << [first_byte, last_byte]
          first_byte = last_byte + 1
        end
        ranges
      end

      def part_meta_path(part)
        "#{part}.meta.json"
      end

      def multipart_part?(part)
        return false unless File.file?(part) && File.file?(part_meta_path(part))
        data = read_part_meta(part)
        return false unless data && data[:version].to_i == PART_META_VERSION
        total = data[:total].to_i
        return false unless total > 0 && File.size(part).to_i == total
        ranges = Array(data[:ranges])
        return false if ranges.empty?
        ranges.all? do |range|
          length = range[:end].to_i - range[:start].to_i + 1
          length > 0 && range[:received].to_i >= 0 && range[:received].to_i <= length
        end
      rescue
        false
      end

      def load_multipart_state(part, url, total, connections, probe)
        return nil unless multipart_part?(part)
        state = read_part_meta(part)
        return nil unless state[:url_sha256].to_s == text_sha256(url)
        return nil unless state[:total].to_i == total.to_i
        return nil unless Array(state[:ranges]).length == connections.to_i
        expected_ranges = split_byte_ranges(total, connections)
        state[:ranges].each_with_index do |range, index|
          expected = expected_ranges[index]
          return nil unless range[:start].to_i == expected[0].to_i
          return nil unless range[:end].to_i == expected[1].to_i
        end
        remote_etag = probe[:response_headers]["etag"].to_s
        remote_modified = probe[:response_headers]["last-modified"].to_s
        return nil if !remote_etag.empty? && state[:etag].to_s != remote_etag
        return nil if remote_etag.empty? && !remote_modified.empty? &&
                      state[:last_modified].to_s != remote_modified
        state
      rescue
        nil
      end

      def read_part_meta(part)
        return nil unless defined?(JSON)
        raw = JSON.parse(File.read(part_meta_path(part)).to_s)
        ranges = Array(raw["ranges"]).map do |range|
          {
            :start => range["start"].to_i,
            :end => range["end"].to_i,
            :received => range["received"].to_i
          }
        end
        {
          :version => raw["version"].to_i,
          :url_sha256 => raw["url_sha256"].to_s,
          :total => raw["total"].to_i,
          :etag => raw["etag"].to_s,
          :last_modified => raw["last_modified"].to_s,
          :ranges => ranges
        }
      rescue
        nil
      end

      def write_part_meta(part, state)
        return false unless defined?(JSON)
        path = part_meta_path(part)
        temporary = "#{path}.tmp"
        payload = {
          "version" => state[:version].to_i,
          "url_sha256" => state[:url_sha256].to_s,
          "total" => state[:total].to_i,
          "etag" => state[:etag].to_s,
          "last_modified" => state[:last_modified].to_s,
          "ranges" => Array(state[:ranges]).map do |range|
            {
              "start" => range[:start].to_i,
              "end" => range[:end].to_i,
              "received" => range[:received].to_i
            }
          end
        }
        File.open(temporary, "wb") { |file| file.write(JSON.generate(payload)) }
        delete_file(path)
        File.rename(temporary, path)
        true
      ensure
        delete_file(temporary) if defined?(temporary) && temporary
      end

      def snapshot_multipart_state(state, shared)
        shared[:mutex].synchronize do
          {
            :version => state[:version],
            :url_sha256 => state[:url_sha256],
            :total => state[:total],
            :etag => state[:etag],
            :last_modified => state[:last_modified],
            :ranges => state[:ranges].map do |range|
              {
                :start => range[:start],
                :end => range[:end],
                :received => range[:received]
              }
            end
          }
        end
      end

      def text_sha256(value)
        digest = sha256_digest
        return "" unless digest
        digest.update(value.to_s)
        digest.hexdigest
      end

      def delete_partial(part)
        delete_file(part)
        delete_file(part_meta_path(part))
        delete_file("#{part_meta_path(part)}.tmp")
      end

      def multipart_cancelled?(shared)
        shared[:mutex].synchronize { shared[:cancelled] }
      rescue
        true
      end

      def stream_with_powershell(url, part, opts)
        executable = powershell_path
        raise_failure(:transport_unavailable, "PowerShell download fallback is unavailable.") unless executable
        temp_root = Reloaded::Platform.temporary_directory
        script = File.join(temp_root, "rld_download_#{Time.now.to_i}_#{rand(100000)}.ps1")
        error_file = "#{script}.error.txt"
        ps = [
          "$ErrorActionPreference = 'Stop'",
          "try {",
          "  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12",
          "  $wc = New-Object Net.WebClient",
          "  $wc.Headers['User-Agent'] = '#{powershell_literal(opts[:headers]["user-agent"])}'",
          "  $wc.DownloadFile('#{powershell_literal(url)}', '#{powershell_literal(part)}')",
          "  exit 0",
          "} catch {",
          "  [IO.File]::WriteAllText('#{powershell_literal(error_file)}', $_.Exception.Message)",
          "  exit 1",
          "}"
        ].join("\n")
        File.open(script, "wb") { |file| file.write(ps) }
        pid = Process.spawn(executable, "-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", script,
                            :out => File::NULL, :err => File::NULL)
        last_bytes = 0
        last_change = Time.now.to_f
        status = nil
        loop do
          checkpoint!(opts[:task])
          finished = Process.waitpid(pid, Process::WNOHANG) rescue nil
          if finished
            status = $?
            break
          end
          bytes = File.file?(part) ? File.size(part).to_i : 0
          if bytes != last_bytes
            last_bytes = bytes
            last_change = Time.now.to_f
          end
          if bytes > opts[:max_bytes]
            terminate_process(pid)
            raise_failure(:file_too_large, "Download exceeded the configured size limit.")
          end
          if Time.now.to_f - last_change > opts[:read_timeout]
            terminate_process(pid)
            raise_failure(:timeout, "Download stopped receiving data.")
          end
          report_bytes(opts[:task], bytes, opts[:expected_bytes], opts)
          sleep(0.1)
        end
        unless status && status.success?
          detail = File.file?(error_file) ? File.read(error_file).to_s : ""
          raise_failure(:transport_failed, sanitize_error(detail, "PowerShell download failed."))
        end
        bytes = File.file?(part) ? File.size(part).to_i : 0
        report_bytes(opts[:task], bytes, opts[:expected_bytes], opts)
        {
          :final_url => url,
          :http_status => 200,
          :content_length => opts[:expected_bytes],
          :bytes => bytes,
          :sha256 => file_sha256(part),
          :headers => {}
        }
      rescue Exception => e
        terminate_process(pid) if defined?(pid) && pid
        raise if e.is_a?(Failure) || cancelled_exception?(e)
        raise_failure(:transport_failed, sanitize_error(e.message, "PowerShell download failed."))
      ensure
        delete_file(script) if defined?(script)
        delete_file(error_file) if defined?(error_file)
      end

      def verify_download!(part, metadata, opts)
        raise_failure(:incomplete_download, "Download did not produce a file.") unless File.file?(part)
        bytes = File.size(part).to_i
        raise_failure(:download_too_small, "Downloaded file is smaller than the required minimum.") if bytes < opts[:min_bytes]
        raise_failure(:file_too_large, "Downloaded file exceeded the configured size limit.") if bytes > opts[:max_bytes]
        announced = metadata[:content_length].to_i
        if announced > 0 && bytes != announced
          raise_failure(:incomplete_download, "Downloaded file size did not match the server response.")
        end
        if opts[:expected_bytes] > 0 && bytes != opts[:expected_bytes]
          raise_failure(:size_mismatch, "Downloaded file size did not match the expected size.")
        end
        actual_hash = metadata[:sha256].to_s.downcase
        actual_hash = file_sha256(part) if actual_hash.empty? && !opts[:sha256].empty?
        if !opts[:sha256].empty? && actual_hash != opts[:sha256]
          raise_failure(:checksum_mismatch, "Downloaded file failed SHA-256 verification.")
        end
        {
          :bytes => bytes,
          :expected_bytes => opts[:expected_bytes] > 0 ? opts[:expected_bytes] : announced,
          :sha256 => actual_hash
        }
      end

      def resumable_part?(part, opts)
        return false unless opts && opts[:resume]
        return true if multipart_part?(part)
        return false unless File.file?(part)
        bytes = File.size(part).to_i
        return false if bytes <= 0 || bytes >= opts[:max_bytes].to_i
        return false if opts[:expected_bytes].to_i > 0 && bytes >= opts[:expected_bytes].to_i
        true
      rescue
        false
      end

      def preserve_partial?(part, opts, error)
        return false unless resumable_part?(part, opts)
        code = error.respond_to?(:code) ? error.code : nil
        [:network_error, :timeout, :incomplete_download,
         :transport_failed, :http_server_error].include?(code)
      rescue
        false
      end

      def response_total_bytes(response, resume_bytes, content_length)
        content_range = response["content-range"].to_s
        if content_range =~ /\Abytes\s+(\d+)-(\d+)\/(\d+|\*)\z/i
          start_byte = Regexp.last_match(1).to_i
          total_text = Regexp.last_match(3)
          raise_failure(:resume_rejected, "The server resumed from the wrong byte.") unless start_byte == resume_bytes.to_i
          return total_text.to_i if total_text != "*" && total_text.to_i > 0
        end
        return 0 if content_length.to_i <= 0
        resume_bytes.to_i + content_length.to_i
      end

      def update_digest_from_file(digest, path)
        return unless digest && File.file?(path)
        File.open(path, "rb") do |file|
          while (chunk = file.read(1024 * 1024))
            digest.update(chunk)
          end
        end
      end

      def validate_announced_size!(bytes, opts)
        return true if bytes.to_i <= 0
        raise_failure(:download_too_small, "Server file is smaller than the required minimum.") if bytes.to_i < opts[:min_bytes]
        raise_failure(:file_too_large, "Server file exceeds the configured size limit.") if bytes.to_i > opts[:max_bytes]
        if opts[:expected_bytes] > 0 && bytes.to_i != opts[:expected_bytes]
          raise_failure(:size_mismatch, "Server file size did not match the expected size.")
        end
        true
      end

      def promote_part!(part, destination)
        backup = "#{destination}.previous"
        delete_file(backup)
        if File.file?(destination)
          File.rename(destination, backup)
        end
        begin
          File.rename(part, destination)
          delete_file(backup)
        rescue Exception
          File.rename(backup, destination) if File.file?(backup) && !File.file?(destination)
          raise
        end
        true
      ensure
        delete_file(backup) if defined?(backup) && File.file?(backup) && File.file?(destination)
      end

      def report_bytes(task, bytes, total, opts)
        stage = "#{download_stage(opts)} - #{format_bytes(bytes)}"
        if total.to_i > 0
          stage += " / #{format_bytes(total)}"
          report(task, bytes.to_f / total.to_f, stage, opts)
        elsif task && task.respond_to?(:indeterminate!)
          task.indeterminate!(stage)
        elsif task
          task.report(nil, stage)
        end
      end

      def report(task, progress, stage, opts)
        return unless task && task.respond_to?(:report)
        low, high = opts[:progress_range]
        mapped = low + (high - low) * [[progress.to_f, 0.0].max, 1.0].min
        task.report(mapped, stage)
        checkpoint!(task)
      end

      def checkpoint!(task)
        task.checkpoint! if task && task.respond_to?(:checkpoint!)
        true
      end

      def complete_stage(opts)
        label = opts[:label].empty? ? "Download" : opts[:label]
        "Downloaded #{label}"
      end

      def download_stage(opts)
        opts[:label].empty? ? "Downloading file" : "Downloading #{opts[:label]}"
      end

      def normalize_headers(headers)
        result = {}
        headers.to_h.each { |key, value| result[key.to_s.downcase] = value.to_s }
        result
      rescue
        {}
      end

      def redirect_headers(headers, from_url, to_url)
        result = headers.dup
        return result if same_origin?(from_url, to_url)
        SENSITIVE_HEADERS.each { |key| result.delete(key) }
        result
      end

      def same_origin?(first, second)
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

      def join_url(base, location)
        URI.join(base.to_s, location.to_s).to_s
      rescue
        location.to_s
      end

      def safe_response_headers(response)
        result = {}
        ["content-length", "content-range", "accept-ranges", "content-type", "etag", "last-modified"].each do |key|
          value = response[key].to_s
          result[key] = value unless value.empty?
        end
        result
      rescue
        {}
      end

      def normalize_sha256(value)
        text = value.to_s.strip.downcase
        return "" if text.empty?
        raise_failure(:invalid_checksum, "SHA-256 must contain exactly 64 hexadecimal characters.") unless text =~ /\A[0-9a-f]{64}\z/
        text
      end

      def sha256_digest
        return Digest::SHA256.new if defined?(Digest::SHA256)
        nil
      rescue
        nil
      end

      def file_sha256(path)
        digest = sha256_digest
        raise_failure(:checksum_unavailable, "SHA-256 verification is unavailable.") unless digest
        File.open(path, "rb") do |file|
          while (chunk = file.read(1024 * 1024))
            digest.update(chunk)
          end
        end
        digest.hexdigest
      end

      def powershell_path
        return nil unless defined?(Reloaded::Platform)
        return nil unless [:windows, :proton].include?(Reloaded::Platform.id)
        root = ENV["SystemRoot"].to_s
        candidate = root.empty? ? nil : File.join(root, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
        return candidate if candidate && File.file?(candidate)
        Reloaded::Platform.id == :windows ? "powershell.exe" : nil
      rescue
        nil
      end

      def powershell_literal(value)
        value.to_s.gsub("'", "''")
      end

      def terminate_process(pid)
        Process.kill("KILL", pid) rescue nil
        Process.waitpid(pid) rescue nil
      end

      def timeout_exception?(error)
        return true if defined?(Timeout::Error) && error.is_a?(Timeout::Error)
        error.class.to_s =~ /Timeout/i
      rescue
        false
      end

      def raise_http_failure(response)
        status = response.code.to_i
        code = status == 429 ? :http_rate_limited : (status >= 500 ? :http_server_error : :http_error)
        retry_after = retry_after_seconds(response["retry-after"])
        raise_failure(code, "Download returned HTTP #{status}.", status, retry_after)
      end

      def retry_after_seconds(value)
        text = value.to_s.strip
        return text.to_f if text =~ /\A\d+(?:\.\d+)?\z/
        parsed = Time.httpdate(text) if Time.respond_to?(:httpdate)
        parsed ? [parsed - Time.now, 0.0].max : 0.0
      rescue
        0.0
      end

      def wait_for_retry(error, retry_index, opts)
        delay = opts[:retry_delay].to_f * (2 ** [retry_index - 1, 0].max)
        delay += rand * [delay * 0.25, 0.5].min
        delay = [delay, error.retry_after.to_f].max if error && error.respond_to?(:retry_after)
        deadline = Time.now.to_f + delay
        while Time.now.to_f < deadline
          checkpoint!(opts[:task])
          sleep([deadline - Time.now.to_f, 0.1].min)
        end
      end

      def with_connection_slot(task)
        unless @connection_mutex && @connection_condition
          return yield
        end
        acquired = false
        until acquired
          checkpoint!(task)
          @connection_mutex.synchronize do
            if @connections_in_use < MAX_CONNECTIONS
              @connections_in_use += 1
              acquired = true
            else
              @connection_condition.wait(@connection_mutex, 0.1)
            end
          end
        end
        yield
      ensure
        if acquired
          @connection_mutex.synchronize do
            @connections_in_use -= 1
            @connections_in_use = 0 if @connections_in_use < 0
            @connection_condition.broadcast
          end
        end
      end

      def ensure_download_space!(part, opts)
        return true unless opts[:disk_space_check]
        expected = opts[:expected_bytes].to_i
        return true if expected <= 0
        ensure_download_space_for_total!(part, expected, opts)
      end

      def ensure_download_space_for_total!(part, expected, opts)
        return true unless opts[:disk_space_check]
        return true unless defined?(Reloaded::Platform) && Reloaded::Platform.respond_to?(:free_disk_bytes)
        free = Reloaded::Platform.free_disk_bytes(File.dirname(part))
        return true unless free
        existing = File.file?(part) ? File.size(part).to_i : 0
        remaining = [expected - existing, 0].max
        required = remaining + DISK_SPACE_MARGIN
        return true if free.to_i >= required
        raise_failure(
          :insufficient_disk_space,
          "Not enough free disk space. Required #{format_bytes(required)}; available #{format_bytes(free)}."
        )
      end

      def terminal_failure?(error)
        [:invalid_url, :invalid_destination, :destination_outside_allowed_roots,
         :destination_is_directory, :unsupported_platform, :invalid_checksum,
         :file_too_large, :download_too_small, :size_mismatch,
         :checksum_unavailable, :http_error, :insufficient_disk_space].include?(error.code)
      rescue
        false
      end

      def retryable_failure?(error)
        RETRYABLE_CODES.include?(error.code)
      rescue
        false
      end

      def cancelled_exception?(error)
        defined?(Reloaded::Task::Cancelled) && error.is_a?(Reloaded::Task::Cancelled)
      rescue
        false
      end

      def failed_result(error, url, destination, started, attempts)
        code = error.respond_to?(:code) ? error.code : :exception
        status = error.respond_to?(:http_status) ? error.http_status : 0
        Result.new(
          :success => false,
          :status => :failed,
          :error_code => code,
          :error_message => sanitize_error(error.message, "Download failed."),
          :url => display_url(url),
          :destination => display_path(destination),
          :duration => elapsed(started),
          :attempts => attempts,
          :http_status => status
        )
      end

      def raise_failure(code, message, http_status = 0, retry_after = 0)
        raise Failure.new(code, message, http_status, retry_after)
      end

      def positive_integer(value, fallback)
        number = value.nil? ? fallback : value.to_i
        number > 0 ? number : fallback
      end

      def positive_number(value, fallback)
        number = value.nil? ? fallback.to_f : value.to_f
        number > 0 ? number : fallback.to_f
      end

      def nonnegative_integer(value, fallback)
        number = value.nil? ? fallback : value.to_i
        number >= 0 ? number : fallback
      end

      def normalize_progress_range(value)
        pair = Array(value)
        return [0.0, 1.0] unless pair.length >= 2
        low = [[pair[0].to_f, 0.0].max, 1.0].min
        high = [[pair[1].to_f, low].max, 1.0].min
        [low, high]
      end

      def ensure_directory(path)
        return if Dir.exist?(path)
        parent = File.dirname(path)
        ensure_directory(parent) if parent && parent != path && !Dir.exist?(parent)
        Dir.mkdir(path)
      end

      def delete_file(path)
        File.delete(path) if path && File.file?(path)
      rescue
      end

      def safe_key(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_-]+/, "_").gsub(/\A_+|_+\z/, "")
      end

      def format_bytes(value)
        bytes = value.to_f
        return "#{bytes.to_i} B" if bytes < 1024
        return format("%.1f KB", bytes / 1024.0) if bytes < 1024 * 1024
        return format("%.1f MB", bytes / (1024.0 * 1024.0)) if bytes < 1024 * 1024 * 1024
        format("%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0))
      end

      def display_path(path)
        return "" if path.to_s.empty?
        return Reloaded::Platform.display_path(path) if defined?(Reloaded::Platform)
        File.basename(path.to_s)
      rescue
        File.basename(path.to_s)
      end

      def display_url(value)
        text = value.to_s
        return text.split("?", 2).first unless defined?(URI)
        uri = URI.parse(text)
        return text.split("?", 2).first unless uri.host
        "#{uri.scheme}://#{uri.host}#{uri.path}"
      rescue
        value.to_s.split("?", 2).first
      end

      def sanitize_error(value, fallback)
        text = value.to_s.gsub(/https:\/\/[^\s?]+\?[^\s]+/i) { |url| url.split("?", 2).first }
        text = Reloaded::Log.sanitize(text) if defined?(Reloaded::Log) && Reloaded::Log.respond_to?(:sanitize)
        text = text.gsub(/[\x00-\x08\x0b\x0c\x0e-\x1f]/, " ").gsub(/\s+/, " ").strip
        text = fallback.to_s if text.empty?
        text.length > MAX_ERROR_TEXT ? text[-MAX_ERROR_TEXT, MAX_ERROR_TEXT] : text
      rescue
        fallback.to_s
      end

      def elapsed(started)
        Time.now - started
      rescue
        0.0
      end

      def log_info(message)
        Reloaded::Log.info(message, :framework) if defined?(Reloaded::Log)
      rescue
      end

      def log_error(message)
        Reloaded::Log.error(message, :framework) if defined?(Reloaded::Log)
      rescue
      end
    end
  end
end
