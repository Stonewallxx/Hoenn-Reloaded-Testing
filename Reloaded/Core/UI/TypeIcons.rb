#======================================================
# Reloaded Type Icons
# Author: Stonewall
#======================================================
# Shared access to Reloaded's labeled and compact type icons.
#======================================================

module Reloaded
  module TypeIcons
    ROOT = "Reloaded/Graphics/Icons"
    FALLBACK = "#{ROOT}/QMARKS"

    @bitmaps = {}

    class << self
      def draw(target, type_id, x, y, style = :badge, width = nil, height = nil)
        source = bitmap(type_id, style)
        return false unless target && source
        draw_width = width || source.width
        draw_height = height || source.height
        source_rect = Rect.new(0, 0, source.width, source.height)
        target.stretch_blt(Rect.new(x, y, draw_width, draw_height), source, source_rect)
        true
      rescue
        false
      end

      def bitmap(type_id, style = :badge)
        path = path_for(type_id, style)
        return nil unless path
        wrapper = @bitmaps[path]
        disposed = wrapper && (wrapper.bitmap.disposed? rescue true)
        if !wrapper || disposed
          wrapper.dispose rescue nil if wrapper
          wrapper = AnimatedBitmap.new(path)
          @bitmaps[path] = wrapper
        end
        wrapper.bitmap
      rescue
        nil
      end

      def path_for(type_id, style = :badge)
        prefix = style.to_sym == :symbol ? "icon" : ""
        candidate = "#{ROOT}/#{prefix}#{file_name(type_id)}"
        return candidate if asset_exists?(candidate)
        asset_exists?(FALLBACK) ? FALLBACK : nil
      rescue
        asset_exists?(FALLBACK) ? FALLBACK : nil
      end

      def file_name(type_id)
        data = GameData::Type.get(type_id)
        data.id.to_s.split("_").map { |part| part.downcase.capitalize }.join
      rescue
        type_id.to_s.split("_").map { |part| part.downcase.capitalize }.join
      end

      def asset_exists?(path)
        return !!pbResolveBitmap(path) if defined?(pbResolveBitmap)
        File.file?(path) || File.file?("#{path}.png")
      rescue
        false
      end
    end
  end
end
