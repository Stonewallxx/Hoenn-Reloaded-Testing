#======================================================
# Reloaded Archive API
# Author: Stonewall
#======================================================
# Safe archive inspection and extraction for Reloaded runtime systems and mods.
# Archive creation remains owned by publishing and backup tools.
#======================================================

begin
  require "open3"
rescue Exception
end

module Reloaded
  module Archive
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    SUPPORTED_EXTENSIONS = [".zip", ".rar", ".7z"].freeze
    SPLIT_ARCHIVE_PATTERN = /\.(?:zip|rar|7z)\.001\z/i
    OVERWRITE_POLICIES = [:overwrite, :skip, :fail].freeze
    DEFAULT_MAX_ENTRIES = 500_000
    DEFAULT_MAX_EXPANDED_BYTES = 40 * 1024 * 1024 * 1024
    DEFAULT_MAX_FILE_BYTES = 8 * 1024 * 1024 * 1024
    DEFAULT_MAX_RATIO = 1_000.0
    MAX_ERROR_TEXT = 700

    class Result
      attr_reader :status, :error_code, :error_message, :entries,
                  :entry_count, :expanded_bytes, :packed_bytes,
                  :archive, :destination, :duration, :warnings

      def initialize(values = {})
        @success = !!values[:success]
        @status = (values[:status] || (@success ? :ok : :failed)).to_sym
        @error_code = values[:error_code] && values[:error_code].to_sym
        @error_message = values[:error_message].to_s
        @entries = Array(values[:entries])
        @entry_count = (values[:entry_count] || @entries.length).to_i
        @expanded_bytes = values[:expanded_bytes].to_i
        @packed_bytes = values[:packed_bytes].to_i
        @archive = values[:archive].to_s
        @destination = values[:destination].to_s
        @duration = values[:duration].to_f
        @warnings = Array(values[:warnings])
      end

      def success?
        @success
      end

      alias ok? success?
    end

    class << self
      def available?
        return false unless defined?(Reloaded::Platform)
        return false unless Reloaded::Platform.supports?(:archive_extract)
        path = Reloaded::Platform.archive_tool_path
        File.file?(path)
      rescue
        false
      end

      def inspect_archive(archive_path, options = {})
        started = Time.now
        opts = normalize_options(options)
        archive = validate_archive_path!(archive_path, opts)
        entries = list_entries(archive)
        validate_entries!(entries, archive, nil, opts)
        totals = entry_totals(entries)
        Result.new(
          :success => true,
          :status => :valid,
          :entries => entries,
          :entry_count => entries.length,
          :expanded_bytes => totals[:expanded],
          :packed_bytes => totals[:packed],
          :archive => display_path(archive),
          :duration => elapsed(started)
        )
      rescue Exception => e
        raise if cancelled_exception?(e)
        failed_result(e, archive_path, nil, started)
      end

      alias list inspect_archive
      alias validate inspect_archive

      def extract(archive_path, destination, options = {})
        started = Time.now
        opts = normalize_options(options)
        task = opts[:task]
        report(task, 0.02, "Checking archive", opts)
        archive = validate_archive_path!(archive_path, opts)
        target = validate_destination!(destination, opts)
        entries = list_entries(archive)
        report(task, 0.12, "Validating archive", opts)
        validate_entries!(entries, archive, target, opts)
        ensure_directory(target)
        report(task, 0.2, "Extracting archive", opts)
        output = run_extraction(archive, target, opts)
        report(task, 0.96, "Verifying extraction", opts)
        verify_expected_files!(entries, target) if opts[:verify]
        report(task, 1.0, "Extraction complete", opts)
        totals = entry_totals(entries)
        result = Result.new(
          :success => true,
          :status => :extracted,
          :entries => opts[:include_entries] ? entries : [],
          :entry_count => entries.length,
          :expanded_bytes => totals[:expanded],
          :packed_bytes => totals[:packed],
          :archive => display_path(archive),
          :destination => display_path(target),
          :duration => elapsed(started)
        )
        log_info("Archive extracted file=#{result.archive} destination=#{result.destination} entries=#{result.entry_count} bytes=#{result.expanded_bytes}")
        result
      rescue Exception => e
        raise if cancelled_exception?(e)
        result = failed_result(e, archive_path, destination, started)
        log_error("Archive extraction failed file=#{result.archive} destination=#{result.destination} code=#{result.error_code} reason=#{result.error_message}")
        result
      end

      def extract!(archive_path, destination, options = {})
        result = extract(archive_path, destination, options)
        raise result.error_message unless result.success?
        result
      end

      private

      def normalize_options(options)
        opts = {}
        (options || {}).each { |key, value| opts[(key.to_sym rescue key)] = value }
        policy = (opts[:overwrite] || :fail).to_sym rescue :fail
        opts[:overwrite] = OVERWRITE_POLICIES.include?(policy) ? policy : :fail
        opts[:max_entries] = positive_limit(opts[:max_entries], DEFAULT_MAX_ENTRIES)
        opts[:max_expanded_bytes] = positive_limit(opts[:max_expanded_bytes], DEFAULT_MAX_EXPANDED_BYTES)
        opts[:max_file_bytes] = positive_limit(opts[:max_file_bytes], DEFAULT_MAX_FILE_BYTES)
        opts[:max_ratio] = positive_float(opts[:max_ratio], DEFAULT_MAX_RATIO)
        opts[:allowed_roots] = allowed_roots
        opts[:progress_range] = normalize_progress_range(opts[:progress_range])
        opts[:verify] = !!opts[:verify]
        opts[:include_entries] = !!opts[:include_entries]
        opts
      end

      def positive_limit(value, fallback)
        number = value.to_i
        number > 0 ? number : fallback
      end

      def positive_float(value, fallback)
        number = value.to_f
        number > 0 ? number : fallback
      end

      def allowed_roots
        roots = [GAME_ROOT]
        roots << Reloaded::Platform.temporary_directory if defined?(Reloaded::Platform)
        roots.map { |root| File.expand_path(root.to_s) }.uniq
      end

      def normalize_progress_range(value)
        pair = Array(value)
        return [0.0, 1.0] unless pair.length >= 2
        low = [[pair[0].to_f, 0.0].max, 1.0].min
        high = [[pair[1].to_f, low].max, 1.0].min
        [low, high]
      end

      def validate_archive_path!(archive_path, opts)
        require_supported_platform!
        path = File.expand_path(archive_path.to_s)
        raise_failure(:archive_missing, "The archive file is missing.") unless File.file?(path)
        raise_failure(:archive_empty, "The archive file is empty.") if File.size(path).to_i <= 0
        extension = File.extname(path).downcase
        supported = SUPPORTED_EXTENSIONS.include?(extension) || path.match?(SPLIT_ARCHIVE_PATTERN)
        raise_failure(:unsupported_format, "Only ZIP, RAR, 7Z, and their numbered split volumes are supported.") unless supported
        validate_allowed_path!(path, opts[:allowed_roots], :archive_outside_allowed_roots, "The archive is outside the allowed folders.")
        path
      end

      def validate_destination!(destination, opts)
        path = File.expand_path(destination.to_s)
        validate_allowed_path!(path, opts[:allowed_roots], :destination_outside_allowed_roots, "The extraction destination is outside the allowed folders.")
        raise_failure(:destination_is_file, "The extraction destination is a file.") if File.file?(path)
        path
      end

      def validate_allowed_path!(path, roots, code, message)
        valid = Array(roots).any? { |root| under_path?(path, root) }
        raise_failure(code, message) unless valid
        true
      end

      def under_path?(path, root)
        target = canonical_path(path)
        base = canonical_path(root)
        target == base || target.start_with?(base + "/")
      end

      def canonical_path(path)
        value = File.expand_path(path.to_s).gsub("\\", "/").sub(/\/+\z/, "")
        case_insensitive_paths? ? value.downcase : value
      end

      def case_insensitive_paths?
        return true unless defined?(Reloaded::Platform)
        [:windows, :proton].include?(Reloaded::Platform.id)
      rescue
        true
      end

      def require_supported_platform!
        unless defined?(Reloaded::Platform) && Reloaded::Platform.supports?(:archive_extract)
          raise_failure(:unsupported_platform, "Archive extraction is unavailable on this platform.")
        end
        raise_failure(:tool_missing, "The bundled archive tool is missing.") unless File.file?(archive_tool)
      end

      def archive_tool
        Reloaded::Platform.archive_tool_path
      end

      def list_entries(archive)
        raise_failure(:process_unavailable, "Archive process support is unavailable.") unless process_supported?
        command = [archive_tool, "l", "-slt", "-ba", "-sccUTF-8", "-bso1", "-bse1", archive]
        rows = []
        current = {}
        output_tail = +""
        line_count = 0
        status = file_backed_process(command) do |line|
          line_count += 1
          append_listing_line(rows, current, line)
          output_tail << line.to_s
          output_tail = output_tail[-8_000, 8_000] if output_tail.length > 8_000
        end
        unless process_success?(status)
          raise_failure(:invalid_archive, process_error("The archive could not be read.", output_tail))
        end
        append_listing_row(rows, current)
        rows.select! { |row| !row[:path].to_s.empty? }
        if rows.empty?
          raise_failure(
            :empty_archive,
            "The archive tool returned no readable file entries from its output file (#{line_count} listing lines)."
          )
        end
        rows
      rescue Failure
        raise
      rescue Exception => e
        raise_failure(:list_failed, sanitize_error(e.message, "The archive could not be inspected."))
      end

      def parse_listing(output)
        rows = []
        current = {}
        output.to_s.each_line { |line| append_listing_line(rows, current, line) }
        append_listing_row(rows, current)
        rows.select { |row| !row[:path].to_s.empty? }
      end

      def append_listing_line(rows, current, line)
        text = line.to_s.sub(/\r?\n\z/, "")
        if text.strip.empty?
          append_listing_row(rows, current)
          return
        end
        match = text.match(/\A\s*([^=]+?)\s*=\s*(.*)\z/)
        return unless match
        key = match[1].to_s.sub(/\A\xEF\xBB\xBF/, "").strip
        current[key] = match[2].to_s
      end

      def append_listing_row(rows, current)
        return if current.empty?
        rows << normalize_listing_row(current)
        current.clear
      end

      def normalize_listing_row(row)
        {
          :path => row["Path"].to_s,
          :folder => row["Folder"].to_s == "+",
          :size => row["Size"].to_i,
          :packed_size => row["Packed Size"].to_i,
          :encrypted => row["Encrypted"].to_s == "+",
          :attributes => row["Attributes"].to_s,
          :symbolic_link => row["Symbolic Link"].to_s,
          :hard_link => row["Hard Link"].to_s
        }
      end

      def validate_entries!(entries, archive, destination, opts)
        raise_failure(:too_many_entries, "The archive contains too many entries.") if entries.length > opts[:max_entries]
        seen = {}
        total = 0
        entries.each do |entry|
          normalized = validate_entry_path!(entry[:path])
          entry[:normalized_path] = normalized
          duplicate_key = case_insensitive_paths? ? normalized.downcase : normalized
          raise_failure(:duplicate_path, "The archive contains duplicate file paths.") if seen[duplicate_key]
          seen[duplicate_key] = true
          raise_failure(:encrypted_archive, "Encrypted archives are not supported.") if entry[:encrypted]
          if link_entry?(entry)
            raise_failure(:link_entry, "Archives containing links are not allowed.")
          end
          size = [entry[:size].to_i, 0].max
          raise_failure(:file_too_large, "The archive contains a file larger than the allowed limit.") if size > opts[:max_file_bytes]
          total += size
          raise_failure(:archive_too_large, "The expanded archive is larger than the allowed limit.") if total > opts[:max_expanded_bytes]
          validate_target_path!(destination, normalized) if destination
        end
        archive_size = [packed_archive_size(archive), 1].max
        ratio = total.to_f / archive_size.to_f
        raise_failure(:compression_ratio, "The archive compression ratio exceeds the safety limit.") if ratio > opts[:max_ratio]
        validate_collisions!(entries, destination, opts[:overwrite]) if destination
        true
      end

      def packed_archive_size(archive)
        return File.size(archive).to_i unless archive.match?(SPLIT_ARCHIVE_PATTERN)
        prefix = archive.sub(/\.001\z/i, "")
        total = 0
        index = 1
        loop do
          part = format("%s.%03d", prefix, index)
          break unless File.file?(part)
          total += File.size(part).to_i
          index += 1
        end
        total
      rescue
        File.size(archive).to_i
      end

      def validate_entry_path!(path)
        raw = path.to_s
        raise_failure(:unsafe_path, "The archive contains an empty file path.") if raw.empty?
        raise_failure(:unsafe_path, "The archive contains an absolute file path.") if raw.start_with?("/", "\\") || raw =~ /\A[A-Za-z]:/
        normalized = raw.tr("\\", "/")
        segments = normalized.split("/")
        cleaned = []
        segments.each do |segment|
          next if segment.empty? || segment == "."
          raise_failure(:path_traversal, "The archive contains a parent-directory path.") if segment == ".."
          raise_failure(:unsafe_path, "The archive contains an invalid file name.") if unsafe_segment?(segment)
          cleaned << segment
        end
        raise_failure(:unsafe_path, "The archive contains an empty file path.") if cleaned.empty?
        normalized = cleaned.join("/")
        raise_failure(:path_too_long, "The archive contains a path that is too long.") if normalized.length > 1_024
        normalized
      end

      def unsafe_segment?(segment)
        return true if segment.length > 255
        return true if segment =~ /[\x00-\x1f]/
        return true if segment.include?(":")
        return true if segment.end_with?(".", " ")
        !!(segment =~ /\A(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?\z/i)
      end

      def link_entry?(entry)
        return true unless entry[:symbolic_link].to_s.empty? && entry[:hard_link].to_s.empty?
        entry[:attributes].to_s =~ /\Al/i
      end

      def validate_target_path!(destination, normalized)
        target = File.expand_path(File.join(destination, *normalized.split("/")))
        raise_failure(:path_traversal, "An archive entry would leave the extraction folder.") unless under_path?(target, destination)
        true
      end

      def validate_collisions!(entries, destination, policy)
        return true unless policy == :fail
        entries.each do |entry|
          target = File.expand_path(File.join(destination, *entry[:normalized_path].split("/")))
          next if entry[:folder] && File.directory?(target)
          if File.exist?(target)
            raise_failure(:destination_collision, "The extraction destination already contains one of the archive files.")
          end
        end
        true
      end

      def run_extraction(archive, destination, opts)
        raise_failure(:process_unavailable, "Archive process support is unavailable.") unless process_supported?
        overwrite = { :overwrite => "-aoa", :skip => "-aos", :fail => "-aos" }[opts[:overwrite]]
        command = [archive_tool, "x", archive, "-y", "-mmt=on", "-bb1", "-bsp1", "-bso1", "-bse1", "-sccUTF-8", overwrite, "-o#{destination}"]
        output = +""
        exit_status = stream_process(command) do |line, _pid|
          output << line.to_s
          output = output[-8_000, 8_000] if output.length > 8_000
          if line.to_s =~ /(\d{1,3})%/
            percent = [[Regexp.last_match(1).to_i, 0].max, 100].min
            report(opts[:task], 0.2 + percent / 100.0 * 0.74, "Extracting archive", opts)
          end
          if opts[:task] && opts[:task].respond_to?(:cancelled?) && opts[:task].cancelled?
            opts[:task].checkpoint!
          end
        end
        unless process_success?(exit_status)
          raise_failure(:extract_failed, process_error("The archive could not be extracted.", output))
        end
        output
      rescue Failure
        raise
      rescue Exception => e
        raise if cancelled_exception?(e)
        raise_failure(:extract_failed, sanitize_error(e.message, "The archive could not be extracted."))
      end

      def process_supported?
        system_supported? || defined?(Open3) ||
          (defined?(Process) && Process.respond_to?(:spawn) && IO.respond_to?(:pipe))
      rescue
        false
      end

      def system_supported?
        Object.private_method_defined?(:system) || Object.method_defined?(:system)
      rescue
        respond_to?(:system, true)
      end

      def process_success?(status)
        return status.success? if status.respond_to?(:success?)
        status == true
      rescue
        false
      end

      def file_backed_process(command)
        raise "System process support is unavailable." unless system_supported?
        output_path = process_output_path
        launched = nil
        File.open(output_path, "wb") do |output|
          launched = system(*command, :out => output, :err => output)
        end
        status = $? || launched
        File.open(output_path, "rb") do |output|
          output.each_line { |line| yield line }
        end
        status
      ensure
        File.delete(output_path) rescue nil if output_path
      end

      def process_output_path
        root = if defined?(Reloaded::Platform) && Reloaded::Platform.respond_to?(:temporary_directory)
                 Reloaded::Platform.temporary_directory
               else
                 GAME_ROOT
               end
        token = "#{Time.now.to_i}_#{Thread.current.object_id}_#{rand(1_000_000)}"
        File.join(root, "archive_output_#{token}.txt")
      end

      def capture_process(command)
        return Open3.capture2e(*command) if defined?(Open3)
        reader = nil
        writer = nil
        pid = nil
        reader, writer = IO.pipe
        pid = Process.spawn(*command, :out => writer, :err => writer)
        writer.close
        output = reader.read
        reader.close
        Process.waitpid(pid)
        status = $?
        pid = nil
        [output, status]
      ensure
        writer.close rescue nil
        reader.close rescue nil
        terminate_process(pid) if pid
      end

      def stream_process(command)
        if defined?(IO) && IO.respond_to?(:popen)
          begin
            status = nil
            IO.popen(command, "r") do |stream|
              stream.each_line { |line| yield line, nil }
            end
            status = $?
            return status
          rescue Exception
          end
        end
        if defined?(Open3)
          status = nil
          Open3.popen2e(*command) do |_input, combined, wait|
            combined.each_line { |line| yield line, wait.pid }
            status = wait.value
          end
          return status
        end
        reader = nil
        writer = nil
        pid = nil
        reader, writer = IO.pipe
        pid = Process.spawn(*command, :out => writer, :err => writer)
        writer.close
        reader.each_line { |line| yield line, pid }
        reader.close
        Process.waitpid(pid)
        status = $?
        pid = nil
        status
      ensure
        writer.close rescue nil
        reader.close rescue nil
        terminate_process(pid) if pid
      end

      def terminate_process(pid)
        return unless pid
        Process.kill("KILL", pid) rescue nil
        Process.waitpid(pid) rescue nil
      end

      def verify_expected_files!(entries, destination)
        entries.each do |entry|
          next if entry[:folder]
          target = File.expand_path(File.join(destination, *entry[:normalized_path].split("/")))
          raise_failure(:verification_failed, "An expected extracted file is missing.") unless File.file?(target)
        end
        true
      end

      def entry_totals(entries)
        {
          :expanded => entries.inject(0) { |sum, entry| sum + [entry[:size].to_i, 0].max },
          :packed => entries.inject(0) { |sum, entry| sum + [entry[:packed_size].to_i, 0].max }
        }
      end

      def report(task, progress, stage, opts)
        return unless task && task.respond_to?(:report)
        low, high = opts[:progress_range]
        mapped = low + (high - low) * [[progress.to_f, 0.0].max, 1.0].min
        task.report(mapped, stage)
        task.checkpoint! if task.respond_to?(:checkpoint!)
      end

      def ensure_directory(path)
        return if Dir.exist?(path)
        parent = File.dirname(path)
        ensure_directory(parent) if parent && parent != path && !Dir.exist?(parent)
        Dir.mkdir(path)
      end

      class Failure < StandardError
        attr_reader :code
        def initialize(code, message)
          @code = code.to_sym
          super(message.to_s)
        end
      end

      def raise_failure(code, message)
        raise Failure.new(code, message)
      end

      def failed_result(error, archive, destination, started)
        code = error.respond_to?(:code) ? error.code : :exception
        Result.new(
          :success => false,
          :status => :failed,
          :error_code => code,
          :error_message => sanitize_error(error.message, "The archive operation failed."),
          :archive => display_path(archive),
          :destination => display_path(destination),
          :duration => elapsed(started)
        )
      end

      def process_error(prefix, output)
        detail = sanitize_error(output, "")
        detail.empty? ? prefix : "#{prefix} #{detail}"
      end

      def sanitize_error(value, fallback)
        text = value.to_s.gsub(GAME_ROOT.to_s, "<game>")
        if defined?(Reloaded::Platform)
          temp = Reloaded::Platform.temporary_directory.to_s
          text = text.gsub(temp, "<temp>") unless temp.empty?
        end
        text = text.gsub(/[\x00-\x08\x0b\x0c\x0e-\x1f]/, " ").gsub(/\s+/, " ").strip
        text = fallback.to_s if text.empty?
        text.length > MAX_ERROR_TEXT ? text[-MAX_ERROR_TEXT, MAX_ERROR_TEXT] : text
      rescue
        fallback.to_s
      end

      def display_path(path)
        return "" if path.to_s.empty?
        return Reloaded::Platform.display_path(path) if defined?(Reloaded::Platform)
        File.basename(path.to_s)
      rescue
        File.basename(path.to_s)
      end

      def elapsed(started)
        Time.now - started
      rescue
        0.0
      end

      def cancelled_exception?(error)
        defined?(Reloaded::Task::Cancelled) && error.is_a?(Reloaded::Task::Cancelled)
      rescue
        false
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
