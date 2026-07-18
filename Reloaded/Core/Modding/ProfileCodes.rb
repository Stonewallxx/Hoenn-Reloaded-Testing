#======================================================
# Reloaded Profile Codes
# Author: Stonewall
#======================================================
# Share-code import/export for Mod Manager profiles.
#
# Responsibilities:
#   - Export profile data as an RLD-code string.
#   - Import profile codes as new profiles without touching existing profiles.
#   - Detect missing mods referenced by imported profile codes.
#   - Keep profile share metadata tied to the Reloaded version.
#
#======================================================

begin
  require "json"
rescue Exception
end

module Reloaded
  module ProfileCodes
    CODE_PREFIX = "RLD-code-"
    FORMAT = "RLD-code"
    CODE_VERSION = 1
    BASE64_URL_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    @booted = false

    class << self
      def boot
        return true if @booted
        Reloaded::Log.info("Profile code system ready", :mods) if defined?(Reloaded::Log)
        @booted = true
        true
      rescue Exception => e
        @booted = false
        Reloaded::Log.exception("Profile code boot failed", e, channel: :mods) if defined?(Reloaded::Log)
        false
      end

      def export_profile(name = nil, preset_name: nil)
        ensure_dependencies
        profile = name ? Reloaded::Profiles.load_profile(name) : Reloaded::Profiles.active
        payload = build_payload(profile, preset_name || profile["name"])
        code = encode_payload(payload)
        Reloaded::Log.info("Exported profile code for #{profile["name"]}", :mods) if defined?(Reloaded::Log)
        code
      end

      def encode_payload(payload)
        ensure_dependencies
        validate_payload(payload)
        CODE_PREFIX + encode_json(payload)
      end

      def decode(code)
        ensure_dependencies
        raw = code.to_s.strip
        raise "Profile code is required" if raw.empty?
        raise "Profile code must start with #{CODE_PREFIX}" unless raw[0, CODE_PREFIX.length] == CODE_PREFIX
        payload = parse_json(decode_json(raw[CODE_PREFIX.length, raw.length].to_s))
        validate_payload(payload)
        payload
      end

      def import_code(code, activate: false, disable_mod_ids: [])
        payload = decode(code)
        data = profile_from_payload(payload)
        disable_ids = normalize_string_array(disable_mod_ids)
        unless disable_ids.empty?
          data["enabled_mods"] = normalize_string_array(data["enabled_mods"]) - disable_ids
          data["disabled_mods"] = (normalize_string_array(data["disabled_mods"]) + disable_ids).uniq
        end
        name = unique_import_name(data["name"])
        data["name"] = name
        data["id"] = normalize_mod_id(name)
        data["notes"] = import_notes(payload)
        saved = Reloaded::Profiles.import_data(data, fallback_name: name, activate: activate, overwrite: false)
        Reloaded::Log.info("Imported profile code as #{saved["name"]}", :mods) if defined?(Reloaded::Log)
        saved
      end

      def missing_mod_ids(code_or_payload)
        payload = code_or_payload.is_a?(Hash) ? code_or_payload : decode(code_or_payload)
        referenced_mod_ids(payload) - available_mod_ids
      end

      def referenced_mod_ids(payload)
        profile = profile_from_payload(payload)
        ids = []
        ids += normalize_string_array(profile["enabled_mods"])
        ids += normalize_string_array(profile["disabled_mods"])
        ids += normalize_string_array(profile["load_order"])
        ids += profile["mod_settings"].keys.map { |key| normalize_mod_id(key) } if profile["mod_settings"].is_a?(Hash)
        ids.uniq.sort
      end

      def download_supported?
        defined?(Reloaded::ModBrowser) && Reloaded::ModBrowser.respond_to?(:download_mods)
      end

      private

      def ensure_dependencies
        raise "JSON parser is not available" unless defined?(JSON)
        raise "Reloaded profiles are not available" unless defined?(Reloaded::Profiles)
      end

      def build_payload(profile, preset_name)
        normalized = normalize_profile(profile, preset_name)
        {
          "format" => FORMAT,
          "version" => CODE_VERSION,
          "preset_name" => preset_name.to_s.empty? ? normalized["name"] : preset_name.to_s,
          "reloaded_version" => (Reloaded.version rescue "0.0.0"),
          "profile" => normalized,
          "mods" => mod_metadata_for(normalized)
        }
      end

      def profile_from_payload(payload)
        return normalize_profile(payload["profile"], payload["preset_name"]) if payload["profile"].is_a?(Hash)
        normalize_profile(payload, payload["preset_name"] || payload["name"])
      end

      def validate_payload(payload)
        raise "Profile code data is invalid" unless payload.is_a?(Hash)
        format = payload["format"].to_s
        unless format.empty? || format == FORMAT || format == "reloaded_profile"
          Reloaded::Log.warning("Profile code unsupported format: #{format}", :mods) if defined?(Reloaded::Log)
          raise "Unsupported profile code format: #{format}"
        end
        raise "Unsupported profile code version" if payload["version"] && payload["version"].to_i > CODE_VERSION
        unless payload["profile"].is_a?(Hash) || looks_like_profile?(payload)
          raise "Profile code does not contain profile data"
        end
        Reloaded::Log.info("Decoded profile code format: #{format.empty? ? "bare_profile" : format}", :mods) if defined?(Reloaded::Log)
        true
      end

      def encode_json(payload)
        json = JSON.generate(payload)
        encode_base64_url(json)
      end

      def decode_json(encoded)
        decode_base64_url(encoded.to_s)
      end

      def encode_base64_url(text)
        bytes = []
        text.to_s.each_byte { |byte| bytes << byte }
        output = ""
        index = 0
        while index < bytes.length
          b0 = bytes[index]
          b1 = bytes[index + 1]
          b2 = bytes[index + 2]
          output << BASE64_URL_ALPHABET[b0 >> 2, 1]
          output << BASE64_URL_ALPHABET[((b0 & 0x03) << 4) | (b1 ? (b1 >> 4) : 0), 1]
          output << BASE64_URL_ALPHABET[((b1 & 0x0f) << 2) | (b2 ? (b2 >> 6) : 0), 1] if b1
          output << BASE64_URL_ALPHABET[b2 & 0x3f, 1] if b2
          index += 3
        end
        output
      end

      def decode_base64_url(text)
        clean = text.to_s.gsub(/\s+/, "")
        raise "Profile code data is invalid" if clean.length % 4 == 1
        bytes = []
        index = 0
        while index < clean.length
          chunk = clean[index, 4].to_s
          values = []
          chunk.split("").each do |char|
            value = BASE64_URL_ALPHABET.index(char)
            raise "Profile code contains invalid characters" if value.nil?
            values << value
          end
          raise "Profile code data is invalid" if values.length < 2
          bytes << ((values[0] << 2) | (values[1] >> 4))
          bytes << (((values[1] & 0x0f) << 4) | (values[2] >> 2)) if values.length > 2
          bytes << (((values[2] & 0x03) << 6) | values[3]) if values.length > 3
          index += 4
        end
        bytes.pack("C*")
      end

      def parse_json(raw)
        stringify_json_keys(JSON.parse(raw))
      end

      def stringify_json_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, child), memo|
            memo[key.to_s] = stringify_json_keys(child)
          end
        when Array
          value.map { |child| stringify_json_keys(child) }
        else
          value
        end
      end

      def looks_like_profile?(payload)
        payload.has_key?("enabled_mods") ||
          payload.has_key?("disabled_mods") ||
          payload.has_key?("load_order") ||
          payload.has_key?("mod_settings")
      end

      def normalize_profile(data, fallback_name)
        source = data.is_a?(Hash) ? data : {}
        {
          "id" => normalize_mod_id(source["id"] || fallback_name),
          "name" => normalize_profile_name(source["name"] || fallback_name),
          "version" => (source["version"] || Reloaded::Profiles::PROFILE_VERSION).to_i,
          "enabled_mods" => normalize_string_array(source["enabled_mods"]),
          "disabled_mods" => normalize_string_array(source["disabled_mods"]),
          "load_order" => normalize_string_array(source["load_order"]),
          "mod_settings" => source["mod_settings"].is_a?(Hash) ? source["mod_settings"] : {},
          "notes" => source["notes"].to_s
        }
      end

      def import_notes(payload)
        name = payload["preset_name"].to_s
        version = payload["reloaded_version"].to_s
        "Imported from #{FORMAT}#{name.empty? ? "" : " preset #{name}"}#{version.empty? ? "" : " for Reloaded #{version}"}."
      end

      def unique_import_name(base_name)
        base = normalize_profile_name(base_name)
        return base unless Reloaded::Profiles.exists?(base)
        index = 2
        loop do
          candidate = "#{base} #{index}"
          return candidate unless Reloaded::Profiles.exists?(candidate)
          index += 1
        end
      end

      def mod_metadata_for(profile)
        referenced = []
        referenced += normalize_string_array(profile["enabled_mods"])
        referenced += normalize_string_array(profile["disabled_mods"])
        referenced += normalize_string_array(profile["load_order"])
        referenced += profile["mod_settings"].keys.map { |key| normalize_mod_id(key) } if profile["mod_settings"].is_a?(Hash)
        referenced.uniq.sort.map do |id|
          row = defined?(Reloaded::ModManager) ? Reloaded::ModManager.mod_row(id) : nil
          {
            "id" => id,
            "name" => row ? row[:name].to_s : id,
            "version" => row ? row[:version].to_s : ""
          }
        end
      end

      def available_mod_ids
        defined?(Reloaded::ModManager) ? Reloaded::ModManager.mod_ids : []
      end

      def normalize_profile_name(name)
        value = name.to_s.strip
        value.empty? ? Reloaded::Profiles::DEFAULT_PROFILE_NAME : value
      end

      def normalize_mod_id(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "")
      end

      def normalize_string_array(value)
        return [] unless value.is_a?(Array)
        value.map { |entry| normalize_mod_id(entry) }.reject { |entry| entry.empty? }.uniq
      end
    end
  end
end
