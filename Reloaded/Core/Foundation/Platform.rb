#======================================================
# Reloaded Platform
# Author: Stonewall
#======================================================
# Platform detection, capabilities, and desktop adapters.
#======================================================

begin
  require "Win32API"
rescue Exception
end

module Reloaded
  module Platform
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    OVERRIDE_SETTING = "platform_override"
    PLATFORM_IDS = [:windows, :proton, :joiplay, :unknown].freeze
    PLATFORM_LABELS = {
      :windows => "Windows",
      :proton => "Proton",
      :joiplay => "JoiPlay",
      :unknown => "Other"
    }.freeze
    CAPABILITIES = {
      :windows => [
        :gameplay, :manual_mods, :mod_manager, :browser_downloads, :downloads,
        :file_browser, :open_path, :open_url, :clipboard, :archive_extract,
        :archive_create, :external_tools, :self_update, :mod_publishing,
        :admin_tools, :moddev_tools, :mouse, :remote_data, :background_tasks
      ],
      :proton => [
        :gameplay, :manual_mods, :mod_manager, :browser_downloads, :downloads,
        :file_browser, :open_path, :open_url, :clipboard, :archive_extract,
        :archive_create, :external_tools, :self_update, :mod_publishing,
        :admin_tools, :moddev_tools, :mouse, :remote_data, :background_tasks
      ],
      :joiplay => [:gameplay, :manual_mods, :mod_manager],
      :unknown => [:gameplay, :manual_mods]
    }.freeze

    @detected_id = nil
    @booted = false

    class << self
      def boot
        return true if @booted
        log_platform
        @booted = true
        true
      rescue Exception => e
        @booted = false
        Reloaded::Log.exception("Platform boot failed", e, channel: :framework) if defined?(Reloaded::Log)
        false
      end

      def id
        override_id || detected_id
      end

      def detected_id
        @detected_id ||= detect
      end

      def label(platform_id = id)
        PLATFORM_LABELS[normalize_id(platform_id)] || PLATFORM_LABELS[:unknown]
      end

      def override
        override_id || :auto
      end

      def set_override(value)
        normalized = normalize_override(value)
        raise "Platform override is only available in Debug or ModDev." unless developer_override_available?
        Reloaded::Settings.set(OVERRIDE_SETTING, normalized == :auto ? "Auto" : label(normalized)) if defined?(Reloaded::Settings)
        normalized
      end

      def reset!
        @detected_id = nil
        @booted = false
        detected_id
      end

      def supports?(capability)
        key = capability.to_s.strip.downcase.to_sym
        return clipboard_available? if key == :clipboard
        return mouse_available? if key == :mouse
        Array(CAPABILITIES[id]).include?(key)
      rescue
        false
      end

      def capabilities
        Array(CAPABILITIES[id]).select { |capability| supports?(capability) }
      end

      def desktop_tools?
        supports?(:external_tools)
      end

      def windows?
        id == :windows
      end

      def proton?
        id == :proton
      end

      def joiplay?
        id == :joiplay
      end

      def open_path(path)
        require_capability!(:open_path)
        normalized = File.expand_path(path.to_s)
        raise "Path does not exist: #{display_path(normalized)}" unless File.exist?(normalized)
        id == :proton && !windows_environment? ? run_linux_open(normalized) : run_windows_open(normalized)
      end

      def open_url(url)
        require_capability!(:open_url)
        value = url.to_s.strip
        raise "URL is empty." if value.empty?
        id == :proton && !windows_environment? ? run_linux_open(value) : run_windows_open(value)
      end

      def clipboard_write(text)
        require_capability!(:clipboard)
        Input.clipboard = text.to_s
        true
      rescue Exception => e
        log_failure(:clipboard, e)
        false
      end

      def clipboard_read
        require_capability!(:clipboard)
        Input.clipboard.to_s
      rescue Exception => e
        log_failure(:clipboard, e)
        ""
      end

      def launch_script(path, working_directory = nil, arguments = nil)
        require_capability!(:external_tools)
        script = File.expand_path(path.to_s)
        raise "Tool is missing: #{display_path(script)}" unless File.exist?(script)
        working_directory ||= File.dirname(script)
        arguments = Array(arguments).compact.map { |argument| argument.to_s }
        if File.extname(script).downcase == ".bat"
          ok = launch_windows_batch(script, working_directory, arguments)
          ok = system("cmd.exe", "/c", "start", "", "/D", working_directory, script, *arguments) if ok.nil?
        else
          ok = launch_proton_terminal(script, working_directory, arguments)
        end
        raise "The operating system could not launch #{File.basename(script)}." unless ok
        true
      rescue Exception => e
        log_failure(:external_tools, e, path)
        raise
      end

      def create_zip(archive, relative_paths, working_directory)
        require_capability!(:archive_create)
        seven_zip = seven_zip_path
        ok = Dir.chdir(working_directory) do
          system(seven_zip, "a", "-tzip", archive, *Array(relative_paths))
        end
        ok && File.exist?(archive)
      rescue Exception => e
        log_failure(:archive_create, e, archive)
        raise
      end

      def extract_archive(archive, destination)
        require_capability!(:archive_extract)
        raise "Reloaded::Archive is unavailable." unless defined?(Reloaded::Archive)
        Reloaded::Archive.extract(archive, destination, :overwrite => :overwrite).success?
      rescue Exception => e
        log_failure(:archive_extract, e, archive)
        raise
      end

      def temporary_directory
        candidates = [ENV["TEMP"], ENV["TMP"], ENV["TMPDIR"]].compact
        candidates << "."
        root = candidates.find { |path| !path.to_s.strip.empty? && Dir.exist?(path.to_s) } || "."
        path = File.expand_path(File.join(root, "HoennReloaded"))
        Dir.mkdir(path) unless Dir.exist?(path)
        path
      end

      def free_disk_bytes(path)
        target = File.expand_path(path.to_s)
        target = File.dirname(target) unless File.directory?(target)
        if defined?(Win32API)
          api = Win32API.new("kernel32", "GetDiskFreeSpaceExW", "PPPP", "I")
          wide_path = (target + "\0").encode("UTF-16LE")
          available = [0].pack("Q")
          total = [0].pack("Q")
          total_free = [0].pack("Q")
          return available.unpack("Q")[0].to_i if api.call(wide_path, available, total, total_free) != 0
        end
        if target =~ /\A([A-Za-z]):/
          drive = Regexp.last_match(1)
          system_root = ENV["SystemRoot"].to_s
          powershell = File.join(system_root, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
          powershell = "powershell.exe" unless File.file?(powershell)
          command = "(New-Object IO.DriveInfo('#{drive}:\\')).AvailableFreeSpace"
          output = IO.popen([powershell, "-NoProfile", "-NonInteractive", "-Command", command], "r") do |stream|
            stream.read
          end
          value = output.to_s.strip.to_i
          return value if value > 0
        end
        if File.respond_to?(:statvfs)
          stats = File.statvfs(target)
          return stats.bavail.to_i * stats.frsize.to_i
        end
        output = IO.popen(["df", "-Pk", target], "r") { |stream| stream.read }
        row = output.to_s.lines.map(&:strip).reject(&:empty?).last.to_s.split(/\s+/)
        return row[-3].to_i * 1024 if row.length >= 4
        nil
      rescue
        nil
      end

      def archive_tool_path
        require_capability!(:archive_extract)
        seven_zip_path
      end

      def user_data_directory
        return File.expand_path(File.join(ENV["APPDATA"], "Hoenn Reloaded")) if id == :windows && !ENV["APPDATA"].to_s.empty?
        home = ENV["HOME"].to_s
        return File.expand_path(File.join(home, ".local", "share", "Hoenn Reloaded")) unless home.empty?
        GAME_ROOT
      end

      def developer_override_available?
        return true if defined?($DEBUG) && $DEBUG
        defined?(Reloaded::Settings) && Reloaded::Settings.bool("moddev", false)
      rescue
        false
      end

      def display_path(path)
        root = GAME_ROOT.to_s.gsub("\\", "/")
        value = path.to_s.gsub("\\", "/")
        return "." if value.casecmp(root) == 0
        return value[(root.length + 1)..-1] if value.downcase.start_with?(root.downcase + "/")
        File.basename(value)
      rescue
        File.basename(path.to_s)
      end

      private

      def detect
        return :joiplay if joiplay_environment?
        return :proton if proton_environment?
        return :windows if windows_environment?
        :unknown
      end

      def override_id
        return nil unless developer_override_available?
        value = defined?(Reloaded::Settings) ? Reloaded::Settings.get(OVERRIDE_SETTING, "Auto") : "Auto"
        normalized = normalize_override(value)
        normalized == :auto ? nil : normalized
      rescue
        nil
      end

      def normalize_override(value)
        key = value.to_s.strip.downcase
        return :auto if key.empty? || key == "auto"
        normalized = normalize_id(key)
        PLATFORM_IDS.include?(normalized) ? normalized : :auto
      end

      def normalize_id(value)
        key = value.to_s.strip.downcase
        return :proton if ["steamdeck", "steam_deck", "steam deck", "steamos"].include?(key)
        return :joiplay if ["android", "joiplay"].include?(key)
        symbol = key.to_sym
        PLATFORM_IDS.include?(symbol) ? symbol : :unknown
      end

      def windows_environment?
        probe = [(RUBY_PLATFORM rescue ""), (ENV["OS"] rescue "")].join(" ").downcase
        probe =~ /windows|mingw|mswin|cygwin/
      end

      def proton_environment?
        keys = ["STEAM_COMPAT_DATA_PATH", "STEAM_COMPAT_CLIENT_INSTALL_PATH", "PROTON_VERSION", "WINEPREFIX"]
        keys.any? { |key| !(ENV[key] rescue nil).to_s.strip.empty? }
      end

      def joiplay_environment?
        platform = (RUBY_PLATFORM rescue "").to_s.downcase
        keys = ["JOIPLAY", "ANDROID_ROOT", "ANDROID_DATA"]
        platform.include?("android") || keys.any? { |key| !(ENV[key] rescue nil).to_s.strip.empty? }
      end

      def clipboard_available?
        return false unless Array(CAPABILITIES[id]).include?(:clipboard)
        defined?(Input) && Input.respond_to?(:clipboard) && Input.respond_to?(:clipboard=)
      rescue
        false
      end

      def mouse_available?
        return false unless Array(CAPABILITIES[id]).include?(:mouse)
        defined?(Mouse) || (defined?(Input) && (Input.respond_to?(:mouse_x) || Input.respond_to?(:mouse_in?)))
      rescue
        false
      end

      def require_capability!(capability)
        return true if supports?(capability)
        raise "#{label} does not support #{capability.to_s.gsub('_', ' ')}."
      end

      def seven_zip_path
        path = File.join(GAME_ROOT, "REQUIRED_BY_INSTALLER_UPDATER", "7z.exe")
        raise "7z.exe was not found in REQUIRED_BY_INSTALLER_UPDATER/." unless File.exist?(path)
        path
      end

      def launch_windows_batch(script, working_directory, arguments)
        return nil unless defined?(Win32API)
        shell_execute = Win32API.new(
          "shell32",
          "ShellExecuteW",
          ["L", "P", "P", "P", "P", "L"],
          "L"
        )
        parameters = Array(arguments).map { |argument| quote_windows_argument(argument) }.join(" ")
        result = shell_execute.call(
          0,
          windows_wide_string("open"),
          windows_wide_string(script),
          parameters.empty? ? nil : windows_wide_string(parameters),
          windows_wide_string(working_directory),
          1
        )
        code = result.to_i
        raise "Windows could not open #{File.basename(script)} (ShellExecute code #{code})." unless code > 32
        true
      end

      def quote_windows_argument(argument)
        value = argument.to_s
        return '""' if value.empty?
        return value unless value =~ /[\s"]/
        escaped = value.gsub(/(\\*)\"/) { "#{$1}#{$1}\\\"" }
        escaped = escaped.sub(/(\\+)\z/) { "#{$1}#{$1}" }
        "\"#{escaped}\""
      end

      def windows_wide_string(value)
        (value.to_s + "\0").encode("UTF-16LE")
      end

      def launch_proton_terminal(script, working_directory, arguments = nil)
        arguments = Array(arguments).compact.map { |argument| argument.to_s }
        commands = [
          ["konsole", "--hold", "-e", "sh", script, *arguments],
          ["xterm", "-hold", "-e", "sh", script, *arguments],
          ["gnome-terminal", "--", "sh", script, *arguments]
        ]
        commands.each do |command|
          begin
            pid = Process.spawn(*command, :chdir => working_directory)
            Process.detach(pid)
            return true
          rescue Exception
          end
        end
        if windows_environment?
          return true if system("cmd", "/c", "start", "", "/unix", script, *arguments)
          return true if system("cmd", "/c", "start", "", script, *arguments)
        end
        false
      end

      def run_windows_open(target)
        ok = system("cmd", "/c", "start", "", target)
        raise "Windows could not open the requested target." unless ok
        true
      end

      def run_linux_open(target)
        ok = system("xdg-open", target)
        raise "Proton could not open the requested target with xdg-open." unless ok
        true
      end

      def log_platform
        return unless defined?(Reloaded::Log)
        names = capabilities.map { |value| value.to_s }.join(", ")
        suffix = override == :auto ? "" : " (override; detected #{label(detected_id)})"
        Reloaded::Log.info("Platform: #{label}#{suffix} | Capabilities: #{names}", :framework)
      end

      def log_failure(adapter, error, path = nil)
        return unless defined?(Reloaded::Log)
        context = path ? " for #{display_path(path)}" : ""
        Reloaded::Log.warning("Platform adapter #{adapter} failed#{context}: #{error.class}: #{error.message}", :framework)
      rescue
      end
    end
  end
end
