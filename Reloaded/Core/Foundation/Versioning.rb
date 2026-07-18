#======================================================
# Reloaded Versioning
# Author: Stonewall
#======================================================
# Central semantic version helpers for Reloaded systems and mods.
#======================================================

module Reloaded
  module Versioning
    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    VERSION_FILE = File.join(ROOT, "Version.md")
    BASE_VERSION_FILE = File.join(ROOT, "BaseVersion.md")
    VERSION_PATTERN = /\A\d+\.\d+\.\d+\z/

    class << self
      def current
        read_version(VERSION_FILE)
      end

      def base
        read_version(BASE_VERSION_FILE)
      end

      def valid?(version)
        !!(version.to_s =~ VERSION_PATTERN)
      end

      def parts(version)
        version.to_s.split(".").first(3).map(&:to_i).tap do |values|
          values << 0 while values.length < 3
        end
      end

      def compare(left, right)
        left_parts = parts(left)
        right_parts = parts(right)
        3.times do |index|
          result = left_parts[index] <=> right_parts[index]
          return result unless result == 0
        end
        0
      end

      def at_least?(version, minimum)
        compare(version, minimum) >= 0
      end

      def requirement_met?(minimum, version = current)
        minimum.to_s.empty? || at_least?(version, minimum)
      end

      private

      def read_version(path)
        value = File.file?(path) ? File.read(path).to_s.strip : ""
        value.empty? ? "0.0.0" : value
      rescue
        "0.0.0"
      end
    end
  end
end
