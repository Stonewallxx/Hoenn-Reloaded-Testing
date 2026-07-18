#======================================================
# Reloaded Assets
# Author: Stonewall
#======================================================
# Runtime asset resolver for Reloaded mods.
#
# Responsibilities:
#   - Register active mod asset files without copying them into vanilla folders.
#   - Resolve Graphics, Audio, and Fonts paths to active mod files first.
#   - Patch common Ruby asset-loading helpers to use Reloaded assets.
#   - Log asset conflicts and resolution behavior for debugging.
#
#======================================================

module Reloaded
  module Assets
    ASSET_ROOTS = ["Graphics", "Audio", "Fonts"].freeze
    IMAGE_EXTENSIONS = [".png", ".gif", ".dat"].freeze
    AUDIO_EXTENSIONS = [".wav", ".mp3", ".ogg", ".mid", ".midi", ".wma"].freeze
    FONT_EXTENSIONS = [".ttf", ".otf"].freeze

    @index = {}
    @entries = []
    @conflicts = []
    @patched = false

    class << self
      def rebuild(active_mods)
        clear
        Array(active_mods).each_with_index { |mod_info, index| register_mod_assets(mod_info, index) }
        log_summary
        true
      rescue Exception => e
        Reloaded::Log.exception("Asset index rebuild failed", e, channel: :assets) if defined?(Reloaded::Log)
        false
      end

      def clear
        @index = {}
        @entries = []
        @conflicts = []
      end

      def entries
        @entries.map(&:dup)
      end

      def conflicts
        @conflicts.map do |conflict|
          copy = conflict.dup
          copy[:mods] = Array(conflict[:mods]).dup
          copy[:files] = Array(conflict[:files]).dup
          copy
        end
      end

      def resolve(path, extensions: nil)
        logical = normalize_logical_path(path)
        return nil if logical.empty? || !mod_asset_path?(logical)
        entry = resolve_entry(logical, extensions || [])
        entry ? entry[:source_path] : nil
      rescue Exception => e
        Reloaded::Log.exception("Asset resolve failed for #{path}", e, channel: :assets) if defined?(Reloaded::Log)
        nil
      end

      def resolve_bitmap(path)
        resolve(path, extensions: IMAGE_EXTENSIONS)
      end

      def resolve_audio(path)
        resolve(path, extensions: AUDIO_EXTENSIONS)
      end

      def resolve_font(path)
        resolve(path, extensions: FONT_EXTENSIONS)
      end

      def exist?(path, extensions = [])
        !resolve(path, extensions: extensions).nil?
      end

      def install_patches
        return true if @patched
        patch_rpg_cache
        patch_animated_bitmap
        patch_bitmap_helpers
        patch_audio_helpers
        patch_file_tests
        @patched = true
        register_patch_point
        Reloaded::Log.info("Installed Reloaded asset resolver patches", :assets) if defined?(Reloaded::Log)
        true
      rescue Exception => e
        Reloaded::Log.exception("Asset resolver patch install failed", e, channel: :assets) if defined?(Reloaded::Log)
        false
      end

      private

      def register_mod_assets(mod_info, load_index)
        folder = mod_info[:folder_path].to_s
        return unless File.directory?(folder)
        ASSET_ROOTS.each do |root|
          root_path = File.join(folder, root)
          next unless File.directory?(root_path)
          Dir[File.join(root_path, "**", "*")].sort.each do |source_path|
            next if File.directory?(source_path)
            register_asset(mod_info, source_path, folder, load_index)
          end
        end
      end

      def register_asset(mod_info, source_path, mod_folder, load_index)
        logical = source_path.sub(mod_folder + File::SEPARATOR, "").gsub("\\", "/")
        entry = {
          :mod_id => mod_info[:id],
          :mod_name => mod_info[:name],
          :source => mod_info[:source],
          :source_path => source_path.gsub("\\", "/"),
          :logical_path => logical,
          :load_index => load_index
        }
        add_entry(logical, entry)
        add_entry(strip_extension(logical), entry)
        @entries << entry
      end

      def add_entry(logical, entry)
        key = normalize_key(logical)
        @index[key] ||= []
        existing = @index[key].find { |candidate| candidate[:mod_id] != entry[:mod_id] }
        record_conflict(key, existing, entry) if existing
        @index[key] << entry
        @index[key].sort_by! { |candidate| candidate[:load_index] }
      end

      def resolve_entry(logical, extensions)
        candidates = []
        keys = [logical, strip_extension(logical)]
        extensions.each { |ext| keys << strip_extension(logical) + ext }
        keys.each do |key|
          list = @index[normalize_key(key)]
          candidates.concat(list) if list
        end
        candidates.uniq.last
      end

      def record_conflict(key, first, second)
        return unless first && second
        conflict_key = "#{key}|#{[first[:mod_id], second[:mod_id]].sort.join('|')}"
        return if @conflicts.any? { |conflict| conflict[:key] == conflict_key }
        conflict = {
          :key => conflict_key,
          :asset => key,
          :mods => [first[:mod_id], second[:mod_id]],
          :winner => second[:mod_id],
          :files => [first[:source_path], second[:source_path]]
        }
        @conflicts << conflict
        log_conflict(conflict)
      end

      def log_conflict(conflict)
        if defined?(Reloaded::Log)
          Reloaded::Log.warning(
            "Asset conflict #{conflict[:asset]} mods=#{conflict[:mods].join(', ')} winner=#{conflict[:winner]}",
            :assets
          )
        end
        return unless defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          "asset_#{conflict[:asset].gsub(/[^a-zA-Z0-9_]+/, '_')}".to_sym,
          :target => conflict[:asset],
          :type => :asset_override,
          :file => conflict[:files].join(", "),
          :owner => :reloaded_assets,
          :priority => 100,
          :reason => "Multiple active mods provide the same asset.",
          :recommended_fix => "Disable one asset override or adjust mod load order in the future Mod Manager.",
          :conflict_group => "asset:#{conflict[:asset]}"
        )
      end

      def log_summary
        Reloaded::Log.info(
          "Asset index built: #{@entries.length} file(s), #{@conflicts.length} conflict(s)",
          :assets
        ) if defined?(Reloaded::Log)
      end

      def normalize_logical_path(path)
        path.to_s.gsub("\\", "/").sub(/\A\.\//, "")
      end

      def normalize_key(path)
        normalize_logical_path(path).downcase
      end

      def strip_extension(path)
        path.to_s.sub(/\.[^\/.]+\z/, "")
      end

      def mod_asset_path?(path)
        ASSET_ROOTS.any? { |root| path == root || path.start_with?(root + "/") }
      end

      def register_patch_point
        return unless defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          :runtime_asset_resolver,
          :target => "RPG::Cache/AnimatedBitmap/audio helpers",
          :type => :wrap,
          :file => __FILE__,
          :owner => :reloaded,
          :priority => 100,
          :reason => "Allows active mod assets to override vanilla assets without copying files.",
          :recommended_fix => "Review Reloaded::Assets if graphics or audio files resolve incorrectly.",
          :conflict_group => "runtime_asset_resolution"
        )
      end

      def patch_rpg_cache
        return unless defined?(RPG::Cache)
        class << RPG::Cache
          unless method_defined?(:reloaded_assets_load_bitmap)
            alias_method :reloaded_assets_load_bitmap, :load_bitmap
            def load_bitmap(folder_name, filename, hue = 0)
              path = folder_name.to_s + filename.to_s
              resolved = Reloaded::Assets.resolve_bitmap(path) if defined?(Reloaded::Assets)
              return reloaded_assets_load_bitmap("", resolved, hue) if resolved
              reloaded_assets_load_bitmap(folder_name, filename, hue)
            end
          end

          unless method_defined?(:reloaded_assets_load_bitmap_path)
            alias_method :reloaded_assets_load_bitmap_path, :load_bitmap_path
            def load_bitmap_path(path, hue = 0)
              resolved = Reloaded::Assets.resolve_bitmap(path) if defined?(Reloaded::Assets)
              reloaded_assets_load_bitmap_path(resolved || path, hue)
            end
          end
        end
      end

      def patch_animated_bitmap
        return unless defined?(AnimatedBitmap)
        AnimatedBitmap.class_eval do
          unless method_defined?(:reloaded_assets_initialize)
            alias_method :reloaded_assets_initialize, :initialize
            def initialize(file, hue = 0)
              resolved = Reloaded::Assets.resolve_bitmap(file) if defined?(Reloaded::Assets)
              reloaded_assets_initialize(resolved || file, hue)
            end
          end
        end
      end

      def patch_bitmap_helpers
        Object.class_eval do
          if private_method_defined?(:pbResolveBitmap) && !private_method_defined?(:reloaded_assets_pbResolveBitmap)
            alias_method :reloaded_assets_pbResolveBitmap, :pbResolveBitmap
            def pbResolveBitmap(path)
              resolved = Reloaded::Assets.resolve_bitmap(path) if defined?(Reloaded::Assets)
              return resolved if resolved
              reloaded_assets_pbResolveBitmap(path)
            end
            private :pbResolveBitmap
          end

          if private_method_defined?(:pbBitmapName) && !private_method_defined?(:reloaded_assets_pbBitmapName)
            alias_method :reloaded_assets_pbBitmapName, :pbBitmapName
            def pbBitmapName(path)
              resolved = Reloaded::Assets.resolve_bitmap(path) if defined?(Reloaded::Assets)
              return resolved if resolved
              reloaded_assets_pbBitmapName(path)
            end
            private :pbBitmapName
          end

          if private_method_defined?(:audioFileExists) && !private_method_defined?(:reloaded_assets_audioFileExists)
            alias_method :reloaded_assets_audioFileExists, :audioFileExists
            def audioFileExists(type, filename)
              base = case type
                     when :BGM then "Audio/BGM/"
                     when :SE then "Audio/SE/"
                     when :ME then "Audio/ME/"
                     when :BGS then "Audio/BGS/"
                     else ""
                     end
              return true if defined?(Reloaded::Assets) && Reloaded::Assets.resolve_audio(base + filename.to_s)
              reloaded_assets_audioFileExists(type, filename)
            end
            private :audioFileExists
          end
        end
      end

      def patch_audio_helpers
        return unless defined?(Audio)
        class << Audio
          unless method_defined?(:reloaded_assets_bgm_play)
            alias_method :reloaded_assets_bgm_play, :bgm_play
            def bgm_play(filename, volume = 100, pitch = 100)
              resolved = Reloaded::Assets.resolve_audio(filename) if defined?(Reloaded::Assets)
              reloaded_assets_bgm_play(resolved || filename, volume, pitch)
            end
          end

          unless method_defined?(:reloaded_assets_me_play)
            alias_method :reloaded_assets_me_play, :me_play
            def me_play(filename, volume = 100, pitch = 100)
              resolved = Reloaded::Assets.resolve_audio(filename) if defined?(Reloaded::Assets)
              reloaded_assets_me_play(resolved || filename, volume, pitch)
            end
          end

          unless method_defined?(:reloaded_assets_bgs_play)
            alias_method :reloaded_assets_bgs_play, :bgs_play
            def bgs_play(filename, volume = 100, pitch = 100)
              resolved = Reloaded::Assets.resolve_audio(filename) if defined?(Reloaded::Assets)
              reloaded_assets_bgs_play(resolved || filename, volume, pitch)
            end
          end

          unless method_defined?(:reloaded_assets_se_play)
            alias_method :reloaded_assets_se_play, :se_play
            def se_play(filename, volume = 100, pitch = 100)
              resolved = Reloaded::Assets.resolve_audio(filename) if defined?(Reloaded::Assets)
              reloaded_assets_se_play(resolved || filename, volume, pitch)
            end
          end
        end
      end

      def patch_file_tests
        return unless defined?(FileTest)
        class << FileTest
          unless method_defined?(:reloaded_assets_audio_exist?)
            alias_method :reloaded_assets_audio_exist?, :audio_exist?
            def audio_exist?(filename)
              return true if defined?(Reloaded::Assets) && Reloaded::Assets.resolve_audio(filename)
              reloaded_assets_audio_exist?(filename)
            end
          end

          unless method_defined?(:reloaded_assets_image_exist?)
            alias_method :reloaded_assets_image_exist?, :image_exist?
            def image_exist?(filename)
              return true if defined?(Reloaded::Assets) && Reloaded::Assets.resolve_bitmap(filename)
              reloaded_assets_image_exist?(filename)
            end
          end
        end
      end
    end
  end
end

Reloaded::Assets.install_patches if defined?(Reloaded::Assets)
