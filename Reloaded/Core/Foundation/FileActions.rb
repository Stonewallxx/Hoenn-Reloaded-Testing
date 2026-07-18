#======================================================
# Reloaded File Actions
# Author: Stonewall
#======================================================
# Shared safe file, folder, clipboard, and export actions.
# All filesystem targets are restricted to the game folder.
#======================================================

module Reloaded
  module FileActions
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))

    class << self
      def resolve(path, type: :any, must_exist: true)
        expanded = expand(path)
        reject_outside!(expanded, GAME_ROOT)
        if must_exist
          raise "File or folder was not found: #{display_path(expanded)}" unless File.exist?(expanded)
          reject_outside!(canonical_path(expanded), canonical_path(GAME_ROOT))
          case type.to_sym
          when :file
            raise "Expected a file: #{display_path(expanded)}" unless File.file?(expanded)
          when :folder, :directory
            raise "Expected a folder: #{display_path(expanded)}" unless File.directory?(expanded)
          end
        else
          reject_outside!(canonical_path(expanded), canonical_path(GAME_ROOT))
        end
        expanded
      end

      def inside_game?(path, must_exist: false)
        expanded = expand(path)
        return false unless inside_path?(expanded, GAME_ROOT)
        return false if must_exist && !File.exist?(expanded)
        inside_path?(canonical_path(expanded), canonical_path(GAME_ROOT))
      rescue
        false
      end

      def open(path)
        target = resolve(path)
        return open_folder(target) if File.directory?(target)
        open_file(target)
      end

      def open_file(path)
        target = resolve(path, :type => :file)
        Reloaded::Platform.open_path(target)
      end

      def open_folder(path)
        target = resolve(path, :type => :folder)
        Reloaded::Platform.open_path(target)
      end

      def copy(text)
        Reloaded::Platform.clipboard_write(sanitize(text))
      end
      alias copy_to_clipboard copy

      def read_clipboard
        Reloaded::Platform.clipboard_read
      end

      def export_file(path, label = nil)
        target = resolve(path, :type => :file)
        unless defined?(Reloaded::Diagnostics) && Reloaded::Diagnostics.respond_to?(:export_file)
          raise "File export tools are not available."
        end
        Reloaded::Diagnostics.export_file(target, label || File.basename(target))
      end

      def export_log(label)
        unless defined?(Reloaded::Diagnostics) && Reloaded::Diagnostics.respond_to?(:export_log)
          raise "Log export tools are not available."
        end
        Reloaded::Diagnostics.export_log(label)
      end

      def export_file_async(path, label = nil, **options)
        target = resolve(path, :type => :file)
        unless defined?(Reloaded::Diagnostics) && Reloaded::Diagnostics.respond_to?(:export_file_async)
          raise "Background file export tools are not available."
        end
        Reloaded::Diagnostics.export_file_async(target, label || File.basename(target), **options)
      end

      def export_log_async(label, **options)
        unless defined?(Reloaded::Diagnostics) && Reloaded::Diagnostics.respond_to?(:export_log_async)
          raise "Background log export tools are not available."
        end
        Reloaded::Diagnostics.export_log_async(label, **options)
      end

      def display_path(path)
        expanded = expand(path)
        if inside_path?(expanded, GAME_ROOT)
          relative = normalized(expanded)[normalized(GAME_ROOT).length..-1].to_s.sub(%r{\A/+}, "")
          return "." if relative.empty?
          return relative
        end
        safe_basename(expanded)
      rescue
        safe_basename(path)
      end

      def sanitize(value)
        return Reloaded::Log.sanitize(value) if defined?(Reloaded::Log) && Reloaded::Log.respond_to?(:sanitize)
        text = value.to_s.gsub("\\", "/")
        root = normalized(GAME_ROOT)
        text.gsub(/#{Regexp.escape(root)}(?=\/|\z)/i, "")
      rescue
        value.to_s
      end

      private

      def expand(path)
        value = path.to_s.strip
        raise "Path is empty." if value.empty?
        raise "Path contains an invalid null character." if value.include?("\0")
        File.expand_path(value, GAME_ROOT)
      end

      def reject_outside!(path, root)
        return true if inside_path?(path, root)
        safe_name = safe_basename(path)
        if defined?(Reloaded::Log)
          Reloaded::Log.warning("Blocked file action outside the game folder: #{safe_name}", :framework)
        end
        raise "Refusing to access a path outside the game folder: #{safe_name}"
      end

      def canonical_path(path)
        expanded = File.expand_path(path.to_s)
        return File.realpath(expanded) if File.exist?(expanded)
        missing = []
        cursor = expanded
        until File.exist?(cursor)
          parent = File.dirname(cursor)
          break if parent == cursor
          missing.unshift(File.basename(cursor))
          cursor = parent
        end
        base = File.exist?(cursor) ? File.realpath(cursor) : cursor
        missing.empty? ? base : File.expand_path(File.join(base, *missing))
      rescue
        expanded || File.expand_path(path.to_s)
      end

      def inside_path?(path, root)
        value = comparison_path(path)
        base = comparison_path(root)
        value == base || value.start_with?(base + "/")
      rescue
        false
      end

      def comparison_path(path)
        value = normalized(File.expand_path(path.to_s)).sub(%r{/+\z}, "")
        windows_filesystem? ? value.downcase : value
      end

      def normalized(path)
        path.to_s.gsub("\\", "/")
      end

      def safe_basename(path)
        normalized(path).split("/").last.to_s
      end

      def windows_filesystem?
        File::ALT_SEPARATOR == "\\" || (RUBY_PLATFORM rescue "").to_s =~ /mswin|mingw|cygwin/i
      rescue
        false
      end
    end
  end
end
