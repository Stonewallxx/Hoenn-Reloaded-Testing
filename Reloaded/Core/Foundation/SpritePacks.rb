#======================================================
# Reloaded Sprite Packs
# Author: Stonewall
#======================================================
# Reads AFI-compatible SPAK v2 per-head sprite packs.
#
# Normal loose files and mod assets keep priority. A packed sprite is copied
# into the disposable Reloaded cache only when the normal resolver cannot find
# it. Packs remain separated into Base and Expanded components.
#======================================================

module Reloaded
  module SpritePacks
    begin
      require "json"
    rescue Exception
    end

    begin
      require "digest/sha2"
    rescue Exception
    end

    ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
    GAME_ROOT = File.expand_path(File.join(ROOT, ".."))
    PACK_ROOT = File.join(GAME_ROOT, "Graphics", "SpritePacks")
    UPDATE_ROOT = File.join(PACK_ROOT, "Updates")
    FULL_MANIFEST_PATH = File.join(PACK_ROOT, "manifest.json")
    CACHE_ROOT = File.join(ROOT, "Cache", "SpritePacks")

    MAGIC = "SPAK".freeze
    INDEX_ENTRY_SIZE = 16
    MAX_ENTRIES_PER_PACK = 100_000
    MAX_SPRITE_BYTES = 32 * 1024 * 1024
    PNG_SIGNATURE_BYTES = [137, 80, 78, 71, 13, 10, 26, 10].freeze

    COMPONENTS = [
      { :id => :base, :folder => "Base", :priority => 200 },
      { :id => :expanded, :folder => "Expanded", :priority => 100 }
    ].freeze

    TYPE_FOLDERS = {
      :CUSTOM => "Custom",
      :AUTOGEN => "Autogen",
      :BASE => "Base"
    }.freeze

    @pack_cache = {}
    @update_layers = nil
    @patched = false

    class Pack
      attr_reader :path, :head_id, :entry_count

      def initialize(path, head_id)
        @path = path
        @head_id = head_id.to_i
        @entry_count = 0
        @data_start = 0
        @entries = {}
        read_index
      end

      def valid?
        !@entries.empty?
      end

      def entry(body_id, alt_letter = "")
        @entries[entry_key(body_id, alt_letter)]
      end

      def entries
        @entries.dup
      end

      def read(entry)
        return nil unless entry
        File.open(@path, "rb") do |file|
          file.seek(@data_start + entry[:offset])
          data = file.read(entry[:length])
          return nil unless data && data.length == entry[:length]
          data
        end
      end

      private

      def read_index
        size = File.size(@path)
        File.open(@path, "rb") do |file|
          raise "Invalid sprite pack header." unless file.read(4) == MAGIC
          count_data = file.read(4)
          raise "Invalid sprite pack count." unless count_data && count_data.length == 4
          @entry_count = count_data.unpack("V")[0].to_i
          if @entry_count <= 0 || @entry_count > MAX_ENTRIES_PER_PACK
            raise "Sprite pack entry count is outside the allowed range."
          end
          @data_start = 8 + (@entry_count * INDEX_ENTRY_SIZE)
          raise "Sprite pack index is truncated." if @data_start > size
          @entry_count.times do
            row = file.read(INDEX_ENTRY_SIZE)
            raise "Sprite pack index is truncated." unless row && row.length == INDEX_ENTRY_SIZE
            body_id, alt_index, offset, length = row.unpack("VVVV")
            validate_entry!(body_id, alt_index, offset, length, size)
            key = entry_key(body_id, alt_index_to_string(alt_index))
            raise "Sprite pack contains a duplicate entry." if @entries[key]
            @entries[key] = {
              :body_id => body_id,
              :alt_index => alt_index,
              :offset => offset,
              :length => length
            }
          end
        end
      end

      def validate_entry!(body_id, alt_index, offset, length, pack_size)
        raise "Sprite pack body ID is invalid." if body_id.to_i < 0
        raise "Sprite pack alternate index is invalid." if alt_index.to_i > 26
        if length.to_i <= 0 || length.to_i > MAX_SPRITE_BYTES
          raise "Sprite pack entry size is outside the allowed range."
        end
        ending = @data_start + offset.to_i + length.to_i
        raise "Sprite pack entry points outside the file." if ending > pack_size
      end

      def entry_key(body_id, alt_letter)
        "#{body_id.to_i}:#{alt_letter.to_s.downcase}"
      end

      def alt_index_to_string(index)
        return "" if index.to_i == 0
        (index.to_i - 1 + "a".ord).chr
      end
    end

    class << self
      def available?
        return true unless update_layers.empty?
        COMPONENTS.any? do |component|
          TYPE_FOLDERS.values.any? do |folder|
            Dir.exist?(File.join(PACK_ROOT, component[:folder], folder))
          end
        end
      rescue
        false
      end

      def materialize(pif_sprite)
        return nil unless pif_sprite
        type = pif_sprite.type.to_sym rescue nil
        head_id = pif_sprite.head_id.to_i
        body_id = type == :BASE ? 0 : pif_sprite.body_id.to_i
        alt_letter = pif_sprite.alt_letter.to_s
        alt_letter = "" if type == :AUTOGEN && alt_letter == "autogen"
        materialize_entry(type, head_id, body_id, alt_letter)
      rescue Exception => e
        log_failure("Packed sprite could not be loaded", e)
        nil
      end

      def materialize_entry(type, head_id, body_id, alt_letter = "")
        type = type.to_sym rescue nil
        return nil unless TYPE_FOLDERS[type]
        return nil if head_id.to_i <= 0 || body_id.to_i < 0
        normalized_alt = normalize_alt(alt_letter)
        each_pack(type, head_id) do |source, pack|
          entry = pack.entry(body_id, normalized_alt)
          next unless entry
          cache_path = cached_sprite_path(source, pack, type, head_id, body_id, normalized_alt)
          return runtime_sprite_path(cache_path) if valid_cached_png?(cache_path, entry[:length])
          data = pack.read(entry)
          raise "Packed sprite data is incomplete." unless valid_png_data?(data)
          write_cache_file(cache_path, data)
          return runtime_sprite_path(cache_path)
        end
        nil
      rescue Exception => e
        log_failure("Packed sprite materialization failed", e)
        nil
      end

      def resolve_bitmap(path)
        parsed = parse_logical_sprite_path(path)
        return nil unless parsed
        materialize_entry(
          parsed[:type],
          parsed[:head_id],
          parsed[:body_id],
          parsed[:alt_letter]
        )
      rescue Exception => e
        log_failure("Packed sprite path resolution failed", e)
        nil
      end

      def entries(type, head_id)
        result = []
        seen = {}
        each_pack(type.to_sym, head_id.to_i) do |source, pack|
          pack.entries.each do |key, entry|
            next if seen[key]
            seen[key] = true
            result << entry.merge(
              :component => source[:component],
              :layer => source[:layer]
            )
          end
        end
        result
      rescue
        []
      end

      def available_alt_letters(type, head_id, body_id = 0)
        type = type.to_sym rescue nil
        return [] unless TYPE_FOLDERS[type]
        target_body = type == :BASE ? 0 : body_id.to_i
        found = {}
        entries(type, head_id).each do |entry|
          next unless entry[:body_id].to_i == target_body
          letter = alt_letter_from_index(entry[:alt_index])
          found[letter] = true if letter
        end
        found.keys.sort_by { |letter| [letter.empty? ? 0 : 1, letter] }
      rescue
        []
      end

      def alt_letter_from_index(index)
        value = index.to_i
        return nil if value < 0 || value > 26
        return "" if value == 0
        (value - 1 + "a".ord).chr
      end

      def entry?(type, head_id, body_id, alt_letter = "")
        type = type.to_sym rescue nil
        return false unless TYPE_FOLDERS[type]
        normalized_alt = normalize_alt(alt_letter)
        each_pack(type, head_id.to_i) do |_component, pack|
          return true if pack.entry(body_id.to_i, normalized_alt)
        end
        false
      rescue
        false
      end

      def pack_health
        summary = {
          :packs => 0,
          :entries => 0,
          :invalid => 0,
          :updates => {},
          :components => {}
        }
        update_layers.each do |layer|
          layer_summary = { :packs => 0, :entries => 0, :invalid => 0 }
          layer[:sources].each do |source|
            TYPE_FOLDERS.each do |_type, folder|
              pattern = File.join(source[:root], folder, "*.pak")
              Dir[pattern].sort.each do |path|
                head_id = File.basename(path, ".pak").to_i
                next if head_id <= 0
                begin
                  pack = Pack.new(path, head_id)
                  layer_summary[:packs] += 1
                  layer_summary[:entries] += pack.entry_count
                rescue
                  layer_summary[:invalid] += 1
                end
              end
            end
          end
          summary[:updates][layer[:id]] = layer_summary
          summary[:packs] += layer_summary[:packs]
          summary[:entries] += layer_summary[:entries]
          summary[:invalid] += layer_summary[:invalid]
        end
        COMPONENTS.each do |component|
          component_summary = { :packs => 0, :entries => 0, :invalid => 0 }
          TYPE_FOLDERS.each do |type, folder|
            pattern = File.join(PACK_ROOT, component[:folder], folder, "*.pak")
            Dir[pattern].sort.each do |path|
              head_id = File.basename(path, ".pak").to_i
              next if head_id <= 0
              begin
                pack = Pack.new(path, head_id)
                component_summary[:packs] += 1
                component_summary[:entries] += pack.entry_count
              rescue
                component_summary[:invalid] += 1
              end
            end
          end
          summary[:components][component[:id]] = component_summary
          summary[:packs] += component_summary[:packs]
          summary[:entries] += component_summary[:entries]
          summary[:invalid] += component_summary[:invalid]
        end
        summary
      end

      def verify_component(component_id)
        component = COMPONENTS.find { |entry| entry[:id] == component_id.to_sym }
        return verification_failure(:unknown_component, "Unknown Spritepack component.") unless component
        root = File.join(PACK_ROOT, component[:folder])
        manifest_path = File.join(root, "manifest.json")
        return verification_failure(:manifest_missing, "The Spritepack manifest is missing.") unless File.file?(manifest_path)
        manifest_text = File.read(manifest_path)
        if manifest_text.length >= 3 && manifest_text[0, 3].unpack("C*") == [239, 187, 191]
          manifest_text = manifest_text[3, manifest_text.length - 3]
        end
        manifest = JSON.parse(manifest_text)
        rows = Array(manifest["packs"])
        asset_rows = Array(manifest["assets"])
        result = {
          :success => true,
          :component => component[:id],
          :packs => rows.length,
          :assets => asset_rows.length,
          :verified => 0,
          :assets_verified => 0,
          :missing => 0,
          :invalid => 0,
          :errors => []
        }
        rows.each do |row|
          relative = normalize_manifest_path(row["path"])
          unless relative
            result[:invalid] += 1
            result[:errors] << "Manifest contains an unsafe pack path."
            next
          end
          path = File.expand_path(File.join(root, *relative.split("/")))
          unless under_path?(path, root) && File.file?(path)
            result[:missing] += 1
            result[:errors] << "A listed Spritepack file is missing."
            next
          end
          expected_size = row["size"].to_i
          expected_sha = row["sha256"].to_s.downcase
          size_ok = expected_size <= 0 || File.size(path).to_i == expected_size
          sha_ok = expected_sha.empty? || sha256_file(path) == expected_sha
          begin
            head_id = File.basename(path, ".pak").to_i
            structure_ok = head_id > 0 && Pack.new(path, head_id).valid?
          rescue
            structure_ok = false
          end
          if size_ok && sha_ok && structure_ok
            result[:verified] += 1
          else
            result[:invalid] += 1
            result[:errors] << "A Spritepack file failed verification."
          end
        end
        asset_rows.each do |row|
          relative = normalize_manifest_asset_path(row["path"])
          unless relative
            result[:invalid] += 1
            result[:errors] << "Manifest contains an unsafe asset path."
            next
          end
          path = File.expand_path(File.join(GAME_ROOT, *relative.split("/")))
          unless under_path?(path, GAME_ROOT) && File.file?(path)
            result[:missing] += 1
            result[:errors] << "A listed Spritepack asset is missing."
            next
          end
          expected_size = row["size"].to_i
          expected_sha = row["sha256"].to_s.downcase
          size_ok = expected_size <= 0 || File.size(path).to_i == expected_size
          sha_ok = expected_sha.empty? || sha256_file(path) == expected_sha
          if size_ok && sha_ok
            result[:assets_verified] += 1
          else
            result[:invalid] += 1
            result[:errors] << "A Spritepack asset failed verification."
          end
        end
        Array(manifest["removed_packs"]).each do |path|
          next if normalize_manifest_path(path)
          result[:invalid] += 1
          result[:errors] << "Manifest contains an unsafe removed-pack path."
        end
        result[:success] = result[:missing] == 0 && result[:invalid] == 0
        result
      rescue Exception => e
        verification_failure(:verification_failed, sanitized_message(e))
      end

      def verify_update(update_id)
        layer = update_layers.find { |entry| entry[:id].to_s == update_id.to_s }
        return verification_failure(:unknown_update, "Unknown Spritepack update.") unless layer
        verify_manifest(layer[:root], layer[:manifest], layer[:id])
      rescue Exception => e
        verification_failure(:verification_failed, sanitized_message(e))
      end

      def installed_updates
        update_layers.map do |layer|
          {
            :id => layer[:id],
            :created_at => layer[:created_at],
            :sequence => layer[:sequence]
          }
        end
      end

      def clear_index
        @pack_cache = {}
        @update_layers = nil
        true
      end

      def install_patches
        return true if @patched
        patch_bitmap_resolver
        patch_sprite_extractor
        patch_battle_sprite_loader
        patch_pokedex_utils
        patch_packed_shiny_cache
        @patched = true
        log_info("Installed packed sprite resolver")
        true
      rescue Exception => e
        log_failure("Packed sprite resolver could not be installed", e)
        false
      end

      def packed_animated_bitmap?(animated_bitmap)
        return false unless animated_bitmap
        path = File.join(
          animated_bitmap.path.to_s,
          animated_bitmap.filename.to_s
        )
        under_path?(File.expand_path(path), CACHE_ROOT)
      rescue
        false
      end

      def runtime_sprite_path(path)
        absolute = File.expand_path(path.to_s)
        return absolute unless under_path?(absolute, GAME_ROOT)
        root = File.expand_path(GAME_ROOT).tr("\\", "/").sub(/\/+\z/, "")
        normalized = absolute.tr("\\", "/")
        normalized[(root.length + 1)..-1]
      rescue
        path.to_s
      end

      def visible_bitmap?(bitmap)
        return false unless bitmap
        return false if bitmap.respond_to?(:disposed?) && bitmap.disposed?
        width = bitmap.width.to_i
        height = bitmap.height.to_i
        return false if width <= 0 || height <= 0
        width.times do |x|
          height.times do |y|
            return true if bitmap.get_pixel(x, y).alpha.to_i > 0
          end
        end
        false
      rescue
        false
      end

      def copy_visible_bitmap(bitmap)
        return nil unless visible_bitmap?(bitmap)
        copy = Bitmap.new(bitmap.width, bitmap.height)
        copy.blt(0, 0, bitmap, Rect.new(0, 0, bitmap.width, bitmap.height))
        copy
      rescue
        copy.dispose if defined?(copy) && copy && !copy.disposed?
        nil
      end

      def base_shiny_cache_path(dex_number, body_shiny, head_shiny)
        dex_number = dex_number.to_i
        return nil if dex_number <= 0
        return nil if defined?(Settings::NB_POKEMON) &&
                      dex_number > Settings::NB_POKEMON
        filename = dex_number.to_s
        filename += "_bodyShiny" if body_shiny
        filename += "_headShiny" if head_shiny
        File.join(
          GAME_ROOT,
          "Graphics",
          "Battlers",
          "Shiny",
          dex_number.to_s,
          "#{filename}.png"
        )
      rescue
        nil
      end

      def discard_blank_shiny_cache(path)
        return false unless path && File.file?(path)
        bitmap = Bitmap.new(runtime_sprite_path(path))
        visible = visible_bitmap?(bitmap)
        bitmap.dispose unless bitmap.disposed?
        return false if visible
        File.delete(path)
        log_info("Removed transparent generated shiny cache")
        true
      rescue Exception => e
        bitmap.dispose if defined?(bitmap) && bitmap && !bitmap.disposed?
        log_failure("Transparent shiny cache could not be removed", e)
        false
      end

      private

      def each_pack(type, head_id)
        folder = TYPE_FOLDERS[type]
        return unless folder
        pack_sources(type, head_id).each do |source|
          path = File.join(source[:root], folder, "#{head_id.to_i}.pak")
          next unless File.file?(path)
          cache_key = path_key(path)
          pack = @pack_cache[cache_key]
          unless pack
            begin
              pack = Pack.new(path, head_id)
              @pack_cache[cache_key] = pack
            rescue Exception => e
              @pack_cache[cache_key] = false
              log_failure("Ignored invalid #{source[:id]} #{type.to_s.downcase} sprite pack", e)
              next
            end
          end
          next unless pack
          yield source, pack
        end
      end

      def pack_sources(type, head_id)
        sources = []
        blocked = {}
        type_folder = TYPE_FOLDERS[type]
        update_layers.each do |layer|
          COMPONENTS.sort_by { |component| -component[:priority].to_i }.each do |component|
            component_id = component[:id]
            relative = File.join(component[:folder], type_folder, "#{head_id.to_i}.pak").tr("\\", "/")
            if layer[:removed_packs][relative]
              blocked[component_id] = true
              next
            end
            next if blocked[component_id]
            source = layer[:sources].find { |entry| entry[:component] == component_id }
            sources << source if source
          end
          legacy = layer[:sources].find { |entry| entry[:component] == :update }
          sources << legacy if legacy
        end
        COMPONENTS.sort_by { |component| -component[:priority].to_i }.each do |component|
          next if blocked[component[:id]]
          sources << {
            :id => component[:id],
            :component => component[:id],
            :layer => :full,
            :folder => component[:folder],
            :cache_folder => File.join("Full", component[:folder]),
            :root => File.join(PACK_ROOT, component[:folder])
          }
        end
        sources
      end

      def update_layers
        return @update_layers if @update_layers
        cutoff = full_update_cutoff
        layers = []
        if Dir.exist?(UPDATE_ROOT)
          Dir.entries(UPDATE_ROOT).sort.each do |name|
            next if name == "." || name == ".."
            root = File.join(UPDATE_ROOT, name)
            next unless Dir.exist?(root)
            id = File.basename(root)
            next unless id =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
            manifest_path = File.join(root, "manifest.json")
            next unless File.file?(manifest_path)
            manifest = read_json_file(manifest_path)
            next unless manifest.is_a?(Hash)
            created_at = manifest["created_at"].to_s
            next if update_compacted?(created_at, cutoff)
            sources = update_component_sources(root, id)
            removed_packs = normalized_removed_packs(manifest["removed_packs"])
            next if sources.empty? && removed_packs.empty?
            layers << {
              :id => id,
              :root => root,
              :manifest => manifest,
              :created_at => created_at,
              :sequence => manifest["sequence"].to_i,
              :removed_packs => removed_packs,
              :sources => sources
            }
          end
        end
        @update_layers = sort_update_layers(layers)
        @update_layers
      rescue Exception => e
        log_failure("Spritepack update layers could not be indexed", e)
        @update_layers = []
      end

      def sort_update_layers(layers)
        Array(layers).sort do |left, right|
          compared = right[:sequence].to_i <=> left[:sequence].to_i
          compared = right[:created_at].to_s <=> left[:created_at].to_s if compared == 0
          compared = right[:id].to_s <=> left[:id].to_s if compared == 0
          compared
        end
      end

      def update_compacted?(created_at, cutoff)
        created = created_at.to_s
        included = cutoff.to_s
        !created.empty? && !included.empty? && created <= included
      end

      def update_component_sources(root, id)
        sources = []
        COMPONENTS.sort_by { |component| -component[:priority].to_i }.each do |component|
          component_root = File.join(root, component[:folder])
          next unless TYPE_FOLDERS.values.any? { |folder| Dir.exist?(File.join(component_root, folder)) }
          sources << {
            :id => "#{id}:#{component[:id]}",
            :component => component[:id],
            :layer => id,
            :folder => component[:folder],
            :cache_folder => File.join("Updates", id, component[:folder]),
            :root => component_root
          }
        end
        if sources.empty? &&
           TYPE_FOLDERS.values.any? { |folder| Dir.exist?(File.join(root, folder)) }
          sources << {
            :id => id,
            :component => :update,
            :layer => id,
            :folder => "",
            :cache_folder => File.join("Updates", id),
            :root => root
          }
        end
        sources
      end

      def normalized_removed_packs(value)
        result = {}
        Array(value).each do |path|
          normalized = normalize_manifest_path(path)
          result[normalized] = true if normalized
        end
        result
      end

      def full_update_cutoff
        return "" unless File.file?(FULL_MANIFEST_PATH)
        manifest = read_json_file(FULL_MANIFEST_PATH)
        manifest.is_a?(Hash) ? manifest["includes_updates_through"].to_s : ""
      rescue
        ""
      end

      def parse_logical_sprite_path(path)
        logical = path.to_s.tr("\\", "/")
        logical = logical.sub(/\.(?:png|gif|dat)\z/i, "")
        case logical
        when %r{\AGraphics/CustomBattlers/(?:local_sprites/)?indexed/(\d+)/(\d+)\.(\d+)([a-z]?)\z}i
          return {
            :type => :CUSTOM,
            :head_id => Regexp.last_match(2).to_i,
            :body_id => Regexp.last_match(3).to_i,
            :alt_letter => Regexp.last_match(4).to_s
          }
        when %r{\AGraphics/Battlers/(\d+)/(\d+)\.(\d+)([a-z]?)\z}i
          return {
            :type => :AUTOGEN,
            :head_id => Regexp.last_match(2).to_i,
            :body_id => Regexp.last_match(3).to_i,
            :alt_letter => Regexp.last_match(4).to_s
          }
        when %r{\AGraphics/CustomBattlers/(?:local_sprites/)?BaseSprites/(\d+)([a-z]?)\z}i
          return {
            :type => :BASE,
            :head_id => Regexp.last_match(1).to_i,
            :body_id => 0,
            :alt_letter => Regexp.last_match(2).to_s
          }
        end
        nil
      end

      def normalize_alt(value)
        text = value.to_s.downcase
        return "" if text.empty?
        raise "Only single-letter sprite alternates can be packed." unless text =~ /\A[a-z]\z/
        text
      end

      def cached_sprite_path(source, pack, type, head_id, body_id, alt_letter)
        folder = TYPE_FOLDERS[type]
        filename = if type == :BASE
                     "#{head_id}#{alt_letter}.png"
                   else
                     "#{head_id}.#{body_id}#{alt_letter}.png"
                   end
        File.join(
          CACHE_ROOT,
          source[:cache_folder],
          pack_cache_fingerprint(pack.path),
          folder,
          head_id.to_s,
          filename
        )
      end

      def pack_cache_fingerprint(path)
        stat = File.stat(path)
        micros = (stat.mtime.to_f * 1_000_000).to_i
        "%x-%x" % [stat.size.to_i, micros]
      rescue
        "current"
      end

      def read_json_file(path)
        text = File.read(path)
        if text.length >= 3 && text[0, 3].unpack("C*") == [239, 187, 191]
          text = text[3, text.length - 3]
        end
        JSON.parse(text)
      end

      def verify_manifest(root, manifest, label)
        rows = Array(manifest["packs"])
        asset_rows = Array(manifest["assets"])
        result = {
          :success => true,
          :component => label,
          :packs => rows.length,
          :assets => asset_rows.length,
          :verified => 0,
          :assets_verified => 0,
          :missing => 0,
          :invalid => 0,
          :errors => []
        }
        rows.each do |row|
          relative = normalize_manifest_path(row["path"])
          unless relative
            result[:invalid] += 1
            result[:errors] << "Manifest contains an unsafe pack path."
            next
          end
          path = File.expand_path(File.join(root, *relative.split("/")))
          unless under_path?(path, root) && File.file?(path)
            result[:missing] += 1
            result[:errors] << "A listed Spritepack file is missing."
            next
          end
          expected_size = row["size"].to_i
          expected_sha = row["sha256"].to_s.downcase
          size_ok = expected_size <= 0 || File.size(path).to_i == expected_size
          sha_ok = expected_sha.empty? || sha256_file(path) == expected_sha
          begin
            head_id = File.basename(path, ".pak").to_i
            structure_ok = head_id > 0 && Pack.new(path, head_id).valid?
          rescue
            structure_ok = false
          end
          if size_ok && sha_ok && structure_ok
            result[:verified] += 1
          else
            result[:invalid] += 1
            result[:errors] << "A Spritepack file failed verification."
          end
        end
        asset_rows.each do |row|
          relative = normalize_manifest_asset_path(row["path"])
          unless relative
            result[:invalid] += 1
            result[:errors] << "Manifest contains an unsafe asset path."
            next
          end
          path = File.expand_path(File.join(GAME_ROOT, *relative.split("/")))
          unless under_path?(path, GAME_ROOT) && File.file?(path)
            result[:missing] += 1
            result[:errors] << "A listed Spritepack asset is missing."
            next
          end
          expected_size = row["size"].to_i
          expected_sha = row["sha256"].to_s.downcase
          size_ok = expected_size <= 0 || File.size(path).to_i == expected_size
          sha_ok = expected_sha.empty? || sha256_file(path) == expected_sha
          if size_ok && sha_ok
            result[:assets_verified] += 1
          else
            result[:invalid] += 1
            result[:errors] << "A Spritepack asset failed verification."
          end
        end
        result[:success] = result[:missing] == 0 && result[:invalid] == 0
        result
      end

      def valid_cached_png?(path, expected_length)
        return false unless File.file?(path)
        return false unless File.size(path).to_i == expected_length.to_i
        File.open(path, "rb") { |file| png_signature?(file.read(8)) }
      rescue
        false
      end

      def valid_png_data?(data)
        data && data.length >= 8 && png_signature?(data[0, 8])
      end

      def png_signature?(data)
        data && data.length == 8 && data.unpack("C*") == PNG_SIGNATURE_BYTES
      end

      def write_cache_file(path, data)
        ensure_directory(File.dirname(path))
        temporary = "#{path}.part"
        File.open(temporary, "wb") do |file|
          file.write(data)
          file.flush
        end
        File.delete(path) if File.file?(path)
        File.rename(temporary, path)
        path
      rescue
        File.delete(temporary) if defined?(temporary) && temporary && File.file?(temporary)
        raise
      end

      def ensure_directory(path)
        return if Dir.exist?(path)
        parent = File.dirname(path)
        ensure_directory(parent) if parent && parent != path && !Dir.exist?(parent)
        Dir.mkdir(path)
      end

      def path_key(path)
        value = File.expand_path(path.to_s).tr("\\", "/")
        File::ALT_SEPARATOR == "\\" ? value.downcase : value
      end

      def normalize_manifest_path(path)
        value = path.to_s.tr("\\", "/")
        return nil if value.empty? || value.start_with?("/") || value =~ /\A[A-Za-z]:/
        parts = value.split("/")
        return nil if parts.any? { |part| part.empty? || part == "." || part == ".." }
        return nil unless value.downcase.end_with?(".pak")
        parts.join("/")
      end

      def normalize_manifest_asset_path(path)
        value = path.to_s.tr("\\", "/")
        return nil if value.empty? || value.start_with?("/") || value =~ /\A[A-Za-z]:/
        parts = value.split("/")
        return nil if parts.any? { |part| part.empty? || part == "." || part == ".." }
        normalized = parts.join("/")
        return nil unless normalized.start_with?("Graphics/") || normalized.start_with?("Audio/")
        normalized
      end

      def under_path?(path, root)
        target = path_key(path)
        base = path_key(root)
        target == base || target.start_with?(base + "/")
      end

      def sha256_file(path)
        raise "SHA-256 support is unavailable." unless defined?(Digest::SHA256)
        digest = Digest::SHA256.new
        File.open(path, "rb") do |file|
          while (chunk = file.read(1024 * 1024))
            digest.update(chunk)
          end
        end
        digest.hexdigest.downcase
      end

      def verification_failure(code, message)
        {
          :success => false,
          :error_code => code.to_sym,
          :error_message => message.to_s,
          :packs => 0,
          :assets => 0,
          :verified => 0,
          :assets_verified => 0,
          :missing => 0,
          :invalid => 0,
          :errors => [message.to_s]
        }
      end

      def sanitized_message(error)
        text = error && error.message.to_s
        text = text.gsub(GAME_ROOT.to_s, "<game>")
        text.empty? ? "Spritepack verification failed." : text
      rescue
        "Spritepack verification failed."
      end

      def patch_bitmap_resolver
        Object.class_eval do
          if private_method_defined?(:pbResolveBitmap) &&
             !private_method_defined?(:reloaded_spritepacks_pbResolveBitmap)
            alias_method :reloaded_spritepacks_pbResolveBitmap, :pbResolveBitmap
            def pbResolveBitmap(path)
              resolved = reloaded_spritepacks_pbResolveBitmap(path)
              return resolved if resolved
              if defined?(Reloaded::SpritePacks)
                packed = Reloaded::SpritePacks.resolve_bitmap(path)
                return packed if packed
              end
              nil
            end
            private :pbResolveBitmap
          end
        end
      end

      def patch_sprite_extractor
        return unless defined?(PIFSpriteExtracter)
        PIFSpriteExtracter.class_eval do
          unless method_defined?(:reloaded_spritepacks_load_sprite)
            alias_method :reloaded_spritepacks_load_sprite, :load_sprite
            def load_sprite(pif_sprite, download_allowed = true)
              spritesheet = getSpritesheetPath(pif_sprite) rescue nil
              if !spritesheet || !pbResolveBitmap(spritesheet)
                packed_type = if defined?(AutogenExtracter) && is_a?(AutogenExtracter)
                                :AUTOGEN
                              elsif defined?(BaseSpriteExtracter) && is_a?(BaseSpriteExtracter)
                                :BASE
                              else
                                :CUSTOM
                              end
                body_id = packed_type == :BASE ? 0 : pif_sprite.body_id.to_i
                packed_alt = pif_sprite.alt_letter.to_s
                if packed_type == :AUTOGEN && packed_alt == "autogen"
                  packed_alt = ""
                end
                packed = if defined?(Reloaded::SpritePacks)
                           Reloaded::SpritePacks.materialize_entry(
                             packed_type,
                             pif_sprite.head_id.to_i,
                             body_id,
                             packed_alt
                           )
                         end
                if !packed && defined?(Reloaded::SpritePacks)
                  alternatives = Reloaded::SpritePacks.available_alt_letters(
                    packed_type,
                    pif_sprite.head_id.to_i,
                    body_id
                  )
                  sprite_name = if packed_type == :BASE
                                  pif_sprite.head_id.to_i.to_s
                                else
                                  "#{pif_sprite.head_id.to_i}.#{body_id}"
                                end
                  main_letters = list_main_sprites_letters(sprite_name) rescue []
                  fallback = (alternatives & main_letters).first ||
                             alternatives.first
                  if fallback
                    pif_sprite.alt_letter = fallback
                    packed = Reloaded::SpritePacks.materialize_entry(
                      packed_type,
                      pif_sprite.head_id.to_i,
                      body_id,
                      fallback
                    )
                  end
                end
                if packed
                  bitmap = AnimatedBitmap.new(packed)
                  scale = get_resize_scale.to_i rescue 1
                  bitmap.scale_bitmap(scale) if scale > 1
                  return bitmap
                end
              end
              reloaded_spritepacks_load_sprite(pif_sprite, download_allowed)
            end
          end
        end
      end

      def patch_battle_sprite_loader
        return unless defined?(BattleSpriteLoader)
        BattleSpriteLoader.class_eval do
          unless method_defined?(:reloaded_spritepacks_select_new_pif_base_sprite)
            alias_method :reloaded_spritepacks_select_new_pif_base_sprite,
                         :select_new_pif_base_sprite
            def select_new_pif_base_sprite(dex_number)
              selected = reloaded_spritepacks_select_new_pif_base_sprite(dex_number)
              return selected unless defined?(Reloaded::SpritePacks)
              return selected if Reloaded::SpritePacks.entry?(
                :BASE,
                dex_number.to_i,
                0,
                selected.alt_letter.to_s
              )
              local = check_for_local_sprite(selected) rescue nil
              return selected if local
              sheet = selected.get_spritesheet_path rescue nil
              return selected if sheet && pbResolveBitmap(sheet)
              alternatives = Reloaded::SpritePacks.available_alt_letters(
                :BASE,
                dex_number.to_i,
                0
              )
              return selected if alternatives.empty?
              main_letters = list_main_sprites_letters(dex_number.to_i.to_s) rescue []
              choices = alternatives & main_letters
              choices = alternatives if choices.empty?
              selected.alt_letter = choices.sample
              selected
            rescue
              selected || reloaded_spritepacks_select_new_pif_base_sprite(dex_number)
            end
          end
        end
      end

      def patch_pokedex_utils
        return unless defined?(PokedexUtils)
        PokedexUtils.class_eval do
          unless method_defined?(:reloaded_spritepacks_getBaseSpritesAlts)
            alias_method :reloaded_spritepacks_getBaseSpritesAlts,
                         :getBaseSpritesAlts
            def getBaseSpritesAlts(dex_number)
              legacy = Array(reloaded_spritepacks_getBaseSpritesAlts(dex_number))
              return legacy unless defined?(Reloaded::SpritePacks)
              packed = Reloaded::SpritePacks.available_alt_letters(
                :BASE,
                dex_number.to_i,
                0
              )
              return legacy if packed.empty?
              sheet = if defined?(BaseSpriteExtracter)
                        File.join(
                          BaseSpriteExtracter::SPRITESHEET_FOLDER_PATH,
                          "#{dex_number}.png"
                        )
                      end
              return (legacy + packed).uniq if sheet && pbResolveBitmap(sheet)
              packed
            rescue
              legacy || []
            end
          end

          unless method_defined?(:reloaded_spritepacks_getFusionSpriteAlts)
            alias_method :reloaded_spritepacks_getFusionSpriteAlts,
                         :getFusionSpriteAlts
            def getFusionSpriteAlts(head_id, body_id)
              legacy = Array(
                reloaded_spritepacks_getFusionSpriteAlts(head_id, body_id)
              )
              return legacy unless defined?(Reloaded::SpritePacks)
              packed = Reloaded::SpritePacks.available_alt_letters(
                :CUSTOM,
                head_id.to_i,
                body_id.to_i
              )
              return legacy if packed.empty?
              sheet_exists = legacy.any? do |letter|
                next false unless defined?(CustomSpriteExtracter)
                path = File.join(
                  CustomSpriteExtracter::SPRITESHEET_FOLDER_PATH,
                  head_id.to_s,
                  "#{head_id}#{letter}.png"
                )
                pbResolveBitmap(path)
              end
              sheet_exists ? (legacy + packed).uniq : packed
            rescue
              legacy || []
            end
          end
        end
      end

      def patch_packed_shiny_cache
        return unless defined?(AnimatedBitmap)
        return unless AnimatedBitmap.method_defined?(:shiftAllColors)
        AnimatedBitmap.class_eval do
          unless method_defined?(:reloaded_spritepacks_shiftAllColors)
            alias_method :reloaded_spritepacks_shiftAllColors, :shiftAllColors
            def shiftAllColors(dex_number, body_shiny, head_shiny)
              unless defined?(Reloaded::SpritePacks) &&
                     Reloaded::SpritePacks.packed_animated_bitmap?(self)
                return reloaded_spritepacks_shiftAllColors(
                  dex_number,
                  body_shiny,
                  head_shiny
                )
              end

              source = Reloaded::SpritePacks.copy_visible_bitmap(bitmap)
              cache_path = Reloaded::SpritePacks.base_shiny_cache_path(
                dex_number,
                body_shiny,
                head_shiny
              )
              Reloaded::SpritePacks.discard_blank_shiny_cache(cache_path)
              result = reloaded_spritepacks_shiftAllColors(
                dex_number,
                body_shiny,
                head_shiny
              )
              Reloaded::SpritePacks.discard_blank_shiny_cache(cache_path)
              if source && !Reloaded::SpritePacks.visible_bitmap?(bitmap)
                self.bitmap = source
                source = nil
                shiftColors(
                  GameData::Species.calculateShinyHueOffset(
                    dex_number,
                    body_shiny,
                    head_shiny
                  )
                )
              end
              result
            ensure
              source.dispose if source && !source.disposed?
            end
          end
        end
      end

      def log_info(message)
        Reloaded::Log.info(message, :assets) if defined?(Reloaded::Log)
      rescue
      end

      def log_failure(message, error)
        if defined?(Reloaded::Log)
          reason = error && error.message.to_s.gsub(GAME_ROOT.to_s, "<game>")
          Reloaded::Log.warning("#{message}: #{reason}", :assets)
        end
      rescue
      end
    end
  end
end

Reloaded::SpritePacks.install_patches if defined?(Reloaded::SpritePacks)
