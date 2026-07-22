#======================================================
# Hoenn Reloaded Expanded Dex Runtime Check
# Author: Stonewall
#======================================================

GAME_ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", "..", ".."))
require "json"

expanded_root = File.join(GAME_ROOT, "Reloaded", "Data", "ExpandedDex")
manifest = JSON.parse(File.read(File.join(expanded_root, "Manifest.json")))
id_map = JSON.parse(File.read(File.join(expanded_root, "ExpandedDexIDs.json")))

module Settings
  NB_POKEMON = 576
  ZAPMOLCUNO_NB = NB_POKEMON * NB_POKEMON + NB_POKEMON + 1
end

NB_POKEMON = Settings::NB_POKEMON
CONST_NB_POKE = Settings::NB_POKEMON
ZAPMOLCUNO_NB = Settings::ZAPMOLCUNO_NB

module GameData
  class TestRecord
    attr_reader :id, :id_number

    def initialize(data)
      @id = data[:id]
      @id_number = data[:id_number].to_i
    end
  end

  module TestRegistry
    def register(data)
      record = TestRecord.new(data)
      self::DATA[record.id] = record
      self::DATA[record.id_number] = record
      record
    end

    def try_get(value)
      self::DATA[value]
    end
  end

  class Move
    DATA = {}
    extend TestRegistry
  end

  class Ability
    DATA = {}
    extend TestRegistry
  end

  class Species < TestRecord
    DATA = {}
    extend TestRegistry
  end
end

module Reloaded
  module Log
    class << self
      def info_once(*_args); end
      def info(*_args); end
      def error(*_args); end
      def exception(*_args); end
    end
  end

  module Events
    def self.on(*_args); end
  end

  module Patches
    def self.register(*_args); end
  end
end

GameData::Species.register(:id => :BULBASAUR, :id_number => 1)
load File.join(GAME_ROOT, "Reloaded", "Core", "DataPatches", "ExpandedDex.rb")

counts = Reloaded::ExpandedDex.last_counts
raise "Expanded Dex was not installed." unless Reloaded::ExpandedDex.available?
raise "Expanded Dex counts are unavailable." unless counts
raise "Unexpected species count." unless counts[:species] == manifest["species_count"].to_i
raise "Unexpected move count." unless counts[:moves] == manifest["move_count"].to_i
raise "Unexpected ability count." unless counts[:abilities] == manifest["ability_count"].to_i

maximum = manifest["max_species_id"].to_i
raise "Unexpected maximum species ID." unless Settings::NB_POKEMON == maximum
raise "Top-level species limit was not updated." unless NB_POKEMON == maximum && CONST_NB_POKE == maximum

expected_triple_base = maximum * maximum + maximum + 1
raise "Triple fusion boundary was not rebased." unless Settings::ZAPMOLCUNO_NB == expected_triple_base

top_entry = id_map.fetch("entries").values.max_by { |entry| entry["id"].to_i }
top_symbol = top_entry.fetch("species").to_sym
raise "Top Expanded species was not injected." unless GameData::Species::DATA[top_symbol].id_number == maximum
raise "Numeric species lookup was not registered." unless GameData::Species::DATA[maximum].id == top_symbol

puts "Expanded Dex runtime check passed."
