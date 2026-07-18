#======================================================
# Reloaded Mart Services
# Author: Stonewall
#======================================================
# Service entry handlers for Reloaded Mart.
#
# Responsibilities:
#   - Keep non-item Mart actions out of the main Mart backend file.
#   - Register built-in service actions.
#   - Keep service purchases atomic through the Mart transaction pipeline.
#
#======================================================

module ReloadedMart
  class ServiceEntryHandler < EntryHandler
    def initialize
      super(:service)
    end

    def validate(line, _context = {})
      if line.quantity.to_i != 1
        return TransactionResult.new(false, :service_quantity_limit,
                                     "This service can only be bought one at a time.")
      end
      case service_key(line.entry)
      when "instant_hatch"
        return TransactionResult.new(false, :no_egg_available,
                                     "You don't have any Eggs to hatch.") unless party_eggs?
        TransactionResult.new(true, :ok, "")
      else
        TransactionResult.new(false, :unknown_service, "This service is unavailable.")
      end
    rescue Exception => e
      ReloadedMart.log_exception("Mart service validation failed", e)
      TransactionResult.new(false, :service_validation_failed, "This service is unavailable.")
    end

    def apply(line, _context = {})
      case service_key(line.entry)
      when "instant_hatch"
        hatch_selected_egg(line, _context)
      else
        TransactionResult.new(false, :unknown_service, "This service is unavailable.")
      end
    rescue Exception => e
      ReloadedMart.log_exception("Mart service application failed", e)
      TransactionResult.new(false, :service_failed, "The service could not be completed.")
    end

    def defer_charge?(line, _context = {})
      service_key(line.entry) == "instant_hatch"
    rescue
      false
    end

    private

    def service_key(entry)
      raw = entry && entry.raw.is_a?(Hash) ? entry.raw : {}
      display = entry && entry.display.is_a?(Hash) ? entry.display : {}
      value = raw["service_key"] || raw[:service_key] || raw["service"] || raw[:service] ||
              display["service_key"] || display[:service_key] || display["service"] || display[:service]
      value.to_s.strip.downcase
    end

    def party
      return [] unless defined?($Trainer) && $Trainer && $Trainer.respond_to?(:party)
      Array($Trainer.party)
    rescue
      []
    end

    def party_eggs?
      party.any? { |pkmn| pkmn && pkmn.respond_to?(:egg?) && pkmn.egg? }
    end

    def hatch_selected_egg(line, context)
      entry = line.entry
      index = choose_egg_index
      return TransactionResult.new(false, :service_cancelled, "No Egg was hatched.") if index.nil? || index < 0
      egg = party[index]
      return TransactionResult.new(false, :no_egg_available, "That Egg is unavailable.") unless egg && egg.egg?
      charge = charge_before_hatch(line, context)
      return charge unless charge.ok?
      original_steps = egg.steps_to_hatch.to_i rescue nil
      begin
        egg.steps_to_hatch = 0 if egg.respond_to?(:steps_to_hatch=)
        pbHatch(egg)
      rescue Exception
        if !original_steps.nil? && egg.respond_to?(:steps_to_hatch=) && egg.egg? == false
          egg.steps_to_hatch = original_steps
        end
        raise
      end
      ReloadedMart.log_info(
        "Mart service complete entry=#{entry&.id} service=instant_hatch party_index=#{index}"
      )
      TransactionResult.new(true, :ok, "Egg hatched.",
                            :service_key => "instant_hatch", :party_index => index)
    end

    def charge_before_hatch(line, context)
      amount = line.total_price.to_i
      currency = line.price_result ? line.price_result.currency : line.entry.currency
      charge = ReloadedMart::Inventory.charge(amount, currency)
      return charge unless charge.ok?
      if context.is_a?(Hash) && amount > 0
        context[:deferred_charges] ||= []
        context[:deferred_charges] << { :amount => amount, :currency => currency }
      end
      pbSEPlay("Mart buy item") rescue nil if amount > 0
      ReloadedMart.log_info("Mart service charged entry=#{line.entry&.id} service=instant_hatch amount=#{amount}")
      charge
    end

    def choose_egg_index
      return -1 unless defined?(PokemonParty_Scene) && defined?(PokemonPartyScreen)
      scene = PokemonParty_Scene.new
      screen = PokemonPartyScreen.new(scene, party)
      screen.pbChooseAblePokemon(proc { |pkmn| pkmn && pkmn.respond_to?(:egg?) && pkmn.egg? }, false)
    end
  end

  register_entry_handler(:service, ServiceEntryHandler.new) if respond_to?(:register_entry_handler)
end
