#======================================================
# Hoenn Reloaded Foundation Checks
# Author: Stonewall
#======================================================

require "rbconfig"
require "json"

GAME_ROOT = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
RELOADED_ROOT = File.join(GAME_ROOT, "Reloaded")
FAILURES = []

def check(label)
  result = yield
  if result
    puts "[OK] #{label}"
  else
    FAILURES << label
    puts "[FAIL] #{label}"
  end
rescue Exception => e
  FAILURES << label
  puts "[FAIL] #{label}: #{e.class}: #{e.message}"
end

Dir.chdir(GAME_ROOT) do
  load File.join(RELOADED_ROOT, "LoadOrder.rb")
  manifest_files = Reloaded::LoadOrder.files

  check("Load manifest has no duplicate entries") do
    normalized = manifest_files.map { |path| path.to_s.gsub("\\", "/").downcase }
    normalized.uniq.length == normalized.length
  end

  check("Every load manifest file exists") do
    manifest_files.all? { |path| File.file?(File.join(RELOADED_ROOT, path)) }
  end

  check("Mart automations load after the backend and before Mart UI") do
    backend = manifest_files.index("Modules/ReloadedMart/Backend.rb")
    featured = manifest_files.index("Modules/ReloadedMart/Automation/DailyFeatured.rb")
    events = manifest_files.index("Modules/ReloadedMart/Automation/EconomyEvents.rb")
    ui = manifest_files.index("Modules/ReloadedMart/UI.rb")
    backend && featured && events && ui &&
      backend < featured && featured < events && events < ui
  end

  check("Every Reloaded Ruby file has valid syntax") do
    Dir[File.join(RELOADED_ROOT, "**", "*.rb")].all? do |path|
      system(RbConfig.ruby, "-c", path, :out => File::NULL, :err => File::NULL)
    end
  end

  tool_ruby_files = Dir[File.join(GAME_ROOT, "ModDev", "**", "*.rb")] +
                    Dir[File.join(GAME_ROOT, "Admin Tools", "**", "*.rb")]
  check("Available ModDev and Admin Tool Ruby has valid syntax") do
    tool_ruby_files.all? do |path|
      system(RbConfig.ruby, "-c", path, :out => File::NULL, :err => File::NULL)
    end
  end

  shipped_source_files = Dir[File.join(RELOADED_ROOT, "**", "*.rb")] +
                         Dir[File.join(GAME_ROOT, "Admin Tools", "**", "*.rb")]
  check("Shipped Ruby does not use unsupported JSON.pretty_generate") do
    forbidden_json_call = "JSON." + "pretty_generate"
    shipped_source_files.none? { |path| File.read(path).include?(forbidden_json_call) }
  end

  audited_text_files = Dir[File.join(RELOADED_ROOT, "**", "*.{rb,md,json,txt}")] +
                       Dir[File.join(GAME_ROOT, "ModDev", "**", "*.{rb,md,bat,sh,py}")]
  local_drive_pattern = /(^|[^A-Za-z])[A-Za-z]:[\\\/]/
  check("Shipped Reloaded files contain no local drive paths") do
    audited_text_files.none? { |path| File.read(path) =~ local_drive_pattern }
  end

  check("Runtime load manifest excludes private and developer tools") do
    manifest_files.none? do |path|
      normalized = path.to_s.gsub("\\", "/").downcase
      normalized.include?("admin tools") || normalized.include?("moddev") || normalized.include?("pre-public")
    end
  end

  ordered_runtime_files = Dir[File.join(RELOADED_ROOT, "Core", "**", "*.rb")] +
                          Dir[File.join(RELOADED_ROOT, "Modules", "**", "*.rb")]
  check("Explicit manifest replaces numeric runtime filenames") do
    ordered_runtime_files.none? { |path| File.basename(path) =~ /^\d{3}[a-z]?_/i }
  end

  bootstrap_hook = File.read(File.join(GAME_ROOT, "Data", "Scripts", "999_Main", "999_Main.rb"))
  legacy_bootstrap_path = "./Reloaded/" + "000" + "_Bootstrap.rb"
  check("Vanilla bootstrap hook targets the organized loader") do
    File.file?(File.join(RELOADED_ROOT, "Bootstrap.rb")) &&
      bootstrap_hook.include?("./Reloaded/Bootstrap.rb") &&
      !bootstrap_hook.include?(legacy_bootstrap_path)
  end

  powershell_installer = File.read(File.join(GAME_ROOT, "Hoenn Reloaded Installer.ps1"))
  python_installer = File.read(File.join(GAME_ROOT, "Hoenn Reloaded Installer.py"))
  reloaded_bootstrap = File.read(File.join(RELOADED_ROOT, "Bootstrap.rb"))
  check("Desktop installers force repair after an interrupted live install") do
    powershell_installer.include?("Reloaded\\InstallerIncomplete.json") &&
      powershell_installer.include?("Write-InstallMarker") &&
      powershell_installer.include?("Remove-InstallMarker") &&
      python_installer.include?("Reloaded\", \"InstallerIncomplete.json") &&
      python_installer.include?("write_install_marker") &&
      python_installer.include?("args.repair = True")
  end
  check("Reloaded blocks boot while an installer recovery marker exists") do
    reloaded_bootstrap.include?("InstallerIncomplete.json") &&
      reloaded_bootstrap.include?("block_incomplete_install") &&
      reloaded_bootstrap.include?("Process.exit!(1)")
  end
  check("Desktop installers atomically promote live install files") do
    powershell_installer.include?("Copy-FileAtomically") &&
      powershell_installer.include?("[IO.File]::Replace") &&
      powershell_installer.include?("CriticalInstallPaths") &&
      python_installer.include?('temporary = destination + ".installing"') &&
      python_installer.include?("os.replace(temporary, destination)")
  end

  required_release_files = [
    "Reloaded/Bootstrap.rb",
    "Reloaded/Documentation/System.md",
    "Reloaded/Documentation/Modding.md",
    "Reloaded/Documentation/Events.md",
    "Reloaded/Documentation/Manager.md",
    "Reloaded/Documentation/DataPatches.md",
    "Reloaded/Changelog.md",
    "Reloaded/ReloadedMartBase.json",
    "Reloaded/Graphics/Pokegear/icon_TMVAULT.png",
    "Reloaded/Graphics/Items/pokevial_charge.png",
    "Reloaded/Graphics/Items/pokevial_refill.png",
    "Reloaded/Graphics/ReloadedMenu/POKEVIAL.png",
    "Reloaded/Graphics/ReloadedMenu/PC.png",
    "Reloaded/Graphics/Backgrounds/statsbackground.png"
  ]
  check("Required public documentation and Reloaded assets exist") do
    required_release_files.all? { |path| File.file?(File.join(GAME_ROOT, path)) }
  end

  documented_paths = []
  generated_documented_paths = [
    "Reloaded/Logging/ValidationReport.txt",
    "Reloaded/InstallerFiles.json",
    "Reloaded/InstallerManifest.json",
    "Reloaded/InstallerIncomplete.json"
  ]
  Dir[File.join(RELOADED_ROOT, "Documentation", "*.md")].each do |document|
    next if File.basename(document).include?("To-Do")
    File.read(document).scan(/`((?:Reloaded|ModDev)\/[^`\r\n]+\.(?:rb|md|json|txt|bat|sh|py))`/) do |match|
      documented_paths << match[0]
    end
  end
  check("Documented Reloaded and ModDev file references resolve") do
    documented_paths.uniq.all? do |path|
      generated_documented_paths.include?(path) || File.file?(File.join(GAME_ROOT, path))
    end
  end

  changelog_lines = File.readlines(File.join(RELOADED_ROOT, "Changelog.md")).map { |line| line.rstrip }
  allowed_changelog_sections = [
    "Features", "Improvement", "Bugfixes", "Visuals & UI",
    "Performance & Audio", "Debug & Modding"
  ]
  changelog_sections = []
  changelog_lines.each_with_index do |line, index|
    next_line = changelog_lines[index + 1].to_s
    changelog_sections << [line, index] if next_line =~ /^-{3,}$/ && !line.empty? && line == line.strip && line !~ /^-+$/
  end
  check("Public changelog uses only approved non-empty sections") do
    changelog_sections.all? do |section, index|
      next false unless allowed_changelog_sections.include?(section)
      following = changelog_sections.map { |_name, position| position }.select { |position| position > index }.min || changelog_lines.length
      changelog_lines[(index + 2)...following].any? { |line| line.start_with?("- ") }
    end
  end

  require "ripper"
  load File.join(RELOADED_ROOT, "Core", "Modding", "ModTools.rb")
  template_api_source = Reloaded::ModderTools.send(:template_api_examples, "foundation_example")
  template_readme_source = Reloaded::ModderTools.send(
    :template_readme,
    "Foundation Example",
    "foundation_example"
  )
  stable_template_apis = [
    "Reloaded::Form",
    "Reloaded::RemoteData",
    "Reloaded::Task",
    "Reloaded::Download",
    "Reloaded::Archive",
    "Reloaded.grant_reward"
  ]
  check("Generated mod API examples are syntax-valid and cover stable integrations") do
    !Ripper.sexp(template_api_source).nil? &&
      stable_template_apis.all? { |api_name| template_api_source.include?(api_name) }
  end
  check("Generated mod documentation states the public API boundary") do
    template_readme_source.include?("contracts are supported integration points") &&
      template_readme_source.include?("methods marked `private`") &&
      template_readme_source.include?("Documentation/APIExamples.rb")
  end

  tracked_output = IO.popen(["git", "ls-files"], &:read)
  git_inventory_ok = $?.nil? || $?.success?
  tracked_files = tracked_output.to_s.lines.map { |line| line.strip.gsub("\\", "/") }
  check("Git inventory is available for release checks") do
    git_inventory_ok
  end
  vanilla_changes_path = File.join(RELOADED_ROOT, "Documentation", "VanillaChanges.md")
  vanilla_changes_text = File.file?(vanilla_changes_path) ? File.read(vanilla_changes_path) : ""
  documented_vanilla_files = vanilla_changes_text.scan(/`([^`\r\n]+)`/)
                                                  .flatten
                                                  .map { |path| path.gsub("\\", "/") }
                                                  .select do |path|
    path == "Game.ini" || path == "mkxp.json" || path.start_with?("Data/Scripts/")
  end.uniq
  check("Manually documented vanilla change files exist") do
    !documented_vanilla_files.empty? &&
      documented_vanilla_files.all? { |path| File.file?(File.join(GAME_ROOT, path)) }
  end
  generated_tracked = tracked_files.select do |path|
    next false if path == "Reloaded/Logging/.gitignore" || path == "Reloaded/Logging/Reports/.gitignore"
    path.start_with?("Admin Tools/") || path.start_with?("Pre-Public/") ||
      path.start_with?("Reloaded/Logging/") || path == "Reloaded/Settings.txt" ||
      path == "Mods/Reloaded/SpritepacksInstalled.json" ||
      (path.start_with?("Mods/Reloaded/Profiles/") && !path.end_with?("/.gitkeep")) ||
      (path =~ %r{\AModDev/(?:Windows|Proton)/.*(?:Report\.txt|\.tmp|\.previous|\.bak)\z}i)
  end
  check("Generated and private release output is not tracked") do
    generated_tracked.empty?
  end

  expected_ignored_paths = [
    "Pre-Public/release-test.txt",
    "Reloaded/Cache/RemoteData/foundation-check.json",
    "Reloaded/Settings.txt.tmp",
    "Reloaded/Logging/ValidationReport.txt.previous",
    "ModDev/Windows/FoundationReport.txt",
    "ModDev/Proton/FoundationReport.txt"
  ]
  check("Release-generated paths are covered by gitignore") do
    expected_ignored_paths.all? do |path|
      system("git", "check-ignore", "-q", path, :out => File::NULL, :err => File::NULL)
    end
  end

  load File.join(RELOADED_ROOT, "Core", "Foundation", "Versioning.rb")
  check("Version sources are centralized") do
    Reloaded::Versioning.current == File.read(File.join(RELOADED_ROOT, "Version.md")).strip &&
      Reloaded::Versioning.base == File.read(File.join(RELOADED_ROOT, "BaseVersion.md")).strip
  end
  check("Semantic version validation and comparison") do
    Reloaded::Versioning.valid?("1.2.3") &&
      !Reloaded::Versioning.valid?("1.2") &&
      Reloaded::Versioning.compare("1.10.0", "1.9.9") > 0 &&
      Reloaded::Versioning.requirement_met?("0.1.0", "0.2.0")
  end

  load File.join(RELOADED_ROOT, "Core", "Foundation", "APIContracts.rb")
  check("API contracts classify and resolve public systems") do
    Reloaded::API.public?(:events) &&
      Reloaded::API.contract(:hooks)[:classification] == :compatibility &&
      !Reloaded::API.available?(:events)
  end
  exposed_contract = Reloaded::API.contract(:events)
  exposed_contract[:classification] = :internal
  check("API contract inspection cannot mutate the registry") do
    Reloaded::API.contract(:events)[:classification] == :stable
  end

  module Reloaded::API::PopupWindow
    SCREEN_W = 512 unless const_defined?(:SCREEN_W, false)
    SCREEN_H = 384 unless const_defined?(:SCREEN_H, false)
    MAX_W = 384 unless const_defined?(:MAX_W, false)
    MAX_H = 288 unless const_defined?(:MAX_H, false)
    MIN_W = 220 unless const_defined?(:MIN_W, false)
    MIN_H = 84 unless const_defined?(:MIN_H, false)
    THEMES = { :hr => {} }.freeze unless const_defined?(:THEMES, false)
  end
  Reloaded.const_set(:PopupWindow, Reloaded::API::PopupWindow) unless Reloaded.const_defined?(:PopupWindow, false)
  def _INTL(text, *values)
    result = text.to_s.dup
    values.each_with_index { |value, index| result.gsub!("{#{index + 1}}", value.to_s) }
    result
  end unless respond_to?(:_INTL, true)
  load File.join(RELOADED_ROOT, "Core", "UI", "ListState.rb")
  list_rows = [
    { :id => :header, :header => true },
    { :id => :alpha },
    { :id => :locked, :disabled => true, :disabled_reason => "Unavailable" },
    { :id => :gamma }
  ]
  list_state = Reloaded::ListState.new(
    :rows => list_rows,
    :visible_rows => 2,
    :row_id => proc { |row, _index| row[:id] },
    :jump_size => 3,
    :wrap => true,
    :jump_wrap => false,
    :remember => true,
    :memory_key => [:foundation_check, :list_state]
  )
  moved_to_disabled = list_state.move_down
  disabled_event = list_state.activate
  list_state.move_down
  remembered_id = list_state.selected_id
  list_state.replace_rows([list_rows[0], list_rows[3], list_rows[1]], :preserve => :id)
  restored_state = Reloaded::ListState.new(
    :rows => list_rows,
    :row_id => proc { |row, _index| row[:id] },
    :remember => true,
    :memory_key => [:foundation_check, :list_state]
  )
  check("List State owns stable selection, disabled activation, scrolling, jumps, and memory") do
    Reloaded::API.available?(:list_state) &&
      moved_to_disabled.moved? && disabled_event.disabled? && disabled_event.reason == "Unavailable" &&
      remembered_id == :gamma && list_state.selected_id == :gamma &&
      restored_state.selected_id == :gamma && Reloaded::ListState::DEFAULT_JUMP_SIZE == 3
  end
  load File.join(RELOADED_ROOT, "Core", "UI", "ListPicker.rb")
  picker_options = Reloaded::ListPicker.normalize_options(:multi_select => true, :search => true, :start_on_back => true)
  picker_rows = Reloaded::ListPicker.normalize_rows([
    { :label => "Items", :header => true },
    { :label => "Potion", :value => :POTION, :status => "x2" },
    { :label => "Locked", :value => :LOCKED, :disabled => true, :disabled_reason => "Unavailable" }
  ], picker_options)
  picker_scene = Reloaded::API::ListPicker::PickerScene.allocate
  filtered_picker_rows = picker_scene.send(:filtered_rows, picker_rows, "potion")
  check("List Picker exposes normalized headers, disabled rows, Done, and Back") do
    Reloaded::API.available?(:list_picker) &&
      Reloaded::API::ListPicker::LIST_JUMP == 3 &&
      picker_options[:controls] &&
      picker_options[:start_on_back] &&
      picker_rows[0][:header] &&
      picker_rows[2][:disabled] && picker_rows[2][:disabled_reason] == "Unavailable" &&
      picker_rows[-2][:kind] == :done && picker_rows[-1][:kind] == :back &&
      picker_rows.none? { |row| row.key?(:icon) || row.key?(:badge) } &&
      filtered_picker_rows.map { |row| row[:label] }.include?("Items") &&
      filtered_picker_rows.map { |row| row[:label] }.include?("Potion") &&
      !filtered_picker_rows.map { |row| row[:label] }.include?("Locked")
  end
  load File.join(RELOADED_ROOT, "Core", "UI", "NumberPicker.rb")
  number_options = Reloaded::NumberPicker.normalize_options(
    :min => 1, :max => 99, :initial => 120, :step => 0, :large_step => 10,
    :show_max_label => true
  )
  digit_options = Reloaded::NumberPicker.normalize_digit_options(
    :min => -10, :max => 999, :initial => 120, :digits => 4
  )
  number_picker_source = File.read(File.join(RELOADED_ROOT, "Core", "UI", "NumberPicker.rb"))
  check("Number Picker separates Kanto-style editor digits from quantity popups") do
    Reloaded::API.available?(:number_picker) &&
      Reloaded::NumberPicker.respond_to?(:confirm) &&
      Reloaded::NumberPicker.respond_to?(:open_quantity) &&
      number_options[:initial] == 99 && number_options[:step] == 1 &&
      number_options[:large_step] == 10 && number_options[:show_max_label] &&
      digit_options[:min] == 0 && digit_options[:max] == 999 &&
      digit_options[:initial] == 120 && digit_options[:digits] == 4 &&
      number_picker_source.include?("DigitScene.new(title, normalized)") &&
      number_picker_source.include?("PickerScene.new(title, normalize_options(options))") &&
      number_picker_source.include?("def adjust_selected_digit") &&
      number_picker_source.include?("def confirm_selection") &&
      number_picker_source.include?("def pulsing_digit_color") &&
      number_picker_source.include?("@slots_y = 48") &&
      number_picker_source.include?("def adjust(amount, allow_wrap)") &&
      number_picker_source.include?("def show_controls_popup") &&
      !number_picker_source.include?("Controls (Y)")
  end
  load File.join(RELOADED_ROOT, "Core", "UI", "ProgressWindow.rb")
  progress_options = Reloaded::ProgressWindow.normalize_options(
    :mode => :unknown, :cancellable => true, :minimum_visible_time => -1, :width => 9_999
  )
  check("Progress Window exposes guarded HR-style task progress options") do
    Reloaded::API.public?(:progress_window) && Reloaded::API.available?(:progress_window) &&
      Reloaded::ProgressWindow.respond_to?(:show) && Reloaded::ProgressWindow.respond_to?(:run) &&
      progress_options[:mode] == :auto && progress_options[:cancellable] &&
      progress_options[:minimum_visible_time] == 0.0 &&
      progress_options[:width] == Reloaded::PopupWindow::MAX_W
  end
  bag_source = File.read(File.join(RELOADED_ROOT, "Modules", "ReloadedBag.rb"))
  check("Reloaded Bag Autosort pocket Back exits the chooser") do
    bag_source.include?("return result.nil? ? -1 : result.to_i") &&
      bag_source.include?("selected_pocket = 0") &&
      bag_source.include?("selected_pocket = choice")
  end
  shared_ui_source = File.read(File.join(RELOADED_ROOT, "Core", "UI", "ReloadedAPIs.rb"))
  list_state_source = File.read(File.join(RELOADED_ROOT, "Core", "UI", "ListState.rb"))
  list_picker_source = File.read(File.join(RELOADED_ROOT, "Core", "UI", "ListPicker.rb"))
  check("Shared list input uses Controls hints and active-only mouse hover") do
    shared_ui_source.include?("module MouseInput") &&
      shared_ui_source.include?("def active_position") &&
      list_picker_source.include?("Reloaded::HintText.draw_footer") &&
      list_picker_source.include?("@list_state.update_input") &&
      list_state_source.include?("Reloaded::MouseInput.active_position")
  end
  options_source = File.read(File.join(RELOADED_ROOT, "Core", "UI", "Options.rb"))
  check("Developer-only platform option ignores stale UI writes") do
    options_source.include?("next unless Reloaded::Platform.developer_override_available?")
  end

  load File.join(RELOADED_ROOT, "Core", "Foundation", "Events.rb")
  Reloaded::Events.clear
  calls = []
  Reloaded::Events.on(:foundation_check, :stable) do |_context|
    calls << :stable
    Reloaded::Events.on(:foundation_check, :late) { |_ctx| calls << :late }
  end
  Reloaded::Events.on(:foundation_check, :stable) do |_context|
    calls << :replacement
    Reloaded::Events.on(:foundation_check, :late) { |_ctx| calls << :late }
  end
  first_count = Reloaded::Events.emit(:foundation_check)
  first_calls = calls.dup
  calls.clear
  second_count = Reloaded::Events.emit(:foundation_check)
  check("Event IDs replace existing handlers") { first_count == 1 && first_calls == [:replacement] }
  check("Event emissions use a stable handler snapshot") { second_count == 2 && calls == [:late, :replacement] }
  exposed_handlers = Reloaded::Events.handlers(:foundation_check)
  exposed_handlers.first[:priority] = -999
  check("Event handler inspection cannot mutate the registry") do
    Reloaded::Events.handlers(:foundation_check).first[:priority] != -999
  end

  load File.join(RELOADED_ROOT, "Core", "Foundation", "Patches.rb")
  Reloaded::Patches.clear
  Reloaded::Patches.register(:first, :target => "FoundationCheck", :type => :replace, :owner => :check)
  Reloaded::Patches.register(:second, :target => "FoundationCheck", :type => :replace, :owner => :other)
  conflict_before = Reloaded::Patches.conflicts("FoundationCheck").length
  Reloaded::Patches.register(
    :second,
    :target => "FoundationCheck",
    :type => :replace,
    :owner => :other,
    :allow_multiple => true
  )
  conflict_after = Reloaded::Patches.conflicts("FoundationCheck").length
  check("Patch re-registration rebuilds stale conflicts") { conflict_before == 1 && conflict_after == 0 }
  exposed_patch = Reloaded::Patches.registered("FoundationCheck").first
  exposed_patch[:target] = "Changed"
  check("Patch inspection cannot mutate the registry") do
    Reloaded::Patches.registered("FoundationCheck").first[:target] == "FoundationCheck"
  end
  Reloaded::Patches.register(:unrelated, :target => "DifferentTarget", :type => :replace, :owner => :check)
  check("Unrelated patch targets do not conflict") do
    Reloaded::Patches.conflicts.none? do |conflict|
      ids = conflict[:patches].map { |patch| patch[:id] }
      ids.include?(:unrelated) && (ids.include?(:first) || ids.include?(:second))
    end
  end

  load File.join(RELOADED_ROOT, "Core", "Foundation", "Settings.rb")
  check("Known settings normalize valid values") do
    Reloaded::Settings.send(:normalize_value, "logging_mode", "developer") == "Developer" &&
      Reloaded::Settings.send(:normalize_value, "moddev", "ON") == "On" &&
      Reloaded::Settings.send(:normalize_value, "platform_override", "joiplay") == "JoiPlay"
  end
  check("Known settings reject invalid values") do
    Reloaded::Settings.send(:normalize_value, "logging_mode", "invalid") == "Developer" &&
      Reloaded::Settings.send(:normalize_value, "platform_override", "invalid") == "Auto"
  end

  module Input
    class << self
      attr_accessor :clipboard
    end
  end unless defined?(Input)
  original_debug = $DEBUG
  $DEBUG = true
  load File.join(RELOADED_ROOT, "Core", "Foundation", "Platform.rb")
  expected = {
    :windows => [true, true, true, true, true],
    :proton => [true, true, true, true, true],
    :joiplay => [false, false, false, false, false]
  }
  matrix_ok = expected.all? do |platform, flags|
    Reloaded::Settings.set("platform_override", Reloaded::Platform.label(platform), :persist => false)
    actual = [
      Reloaded::Platform.supports?(:browser_downloads),
      Reloaded::Platform.supports?(:external_tools),
      Reloaded::Platform.supports?(:remote_data),
      Reloaded::Platform.supports?(:background_tasks),
      Reloaded::Platform.supports?(:downloads)
    ]
    actual == flags
  end
  check("Platform capability matrix") { matrix_ok }

  Reloaded::Settings.set("platform_override", "JoiPlay", :persist => false)
  check("JoiPlay exposes gameplay but hides unsupported desktop tools") do
    Reloaded::Platform.supports?(:gameplay) &&
      Reloaded::Platform.supports?(:manual_mods) &&
      !Reloaded::Platform.supports?(:external_tools) &&
      !Reloaded::Platform.supports?(:admin_tools) &&
      !Reloaded::Platform.supports?(:moddev_tools) &&
      !Reloaded::Platform.supports?(:mod_publishing) &&
      !Reloaded::Platform.supports?(:self_update)
  end

  check("Foundation roots resolve to Reloaded") do
    Reloaded::Settings::ROOT == RELOADED_ROOT &&
      Reloaded::Platform::ROOT == RELOADED_ROOT &&
      Reloaded::Platform::GAME_ROOT == GAME_ROOT
  end
  Reloaded::Settings.set("platform_override", "Windows", :persist => false)
  load File.join(RELOADED_ROOT, "Core", "Foundation", "Download.rb")
  download_test_root = File.join(RELOADED_ROOT, "Cache", "Download", "foundation_check")
  download_target = File.join(download_test_root, "payload.bin")
  Reloaded::Download.send(:ensure_directory, download_test_root)
  download_payload = "foundation-download-payload"
  download_hash = Digest::SHA256.hexdigest(download_payload)
  File.open(download_target, "wb") { |file| file.write("previous-payload") }
  download_attempts = 0
  Reloaded::Download.transport_override = proc do |_url, part, _options, _task|
    download_attempts += 1
    raise Reloaded::Download::Failure.new(:network_error, "Expected retry") if download_attempts == 1
    File.open(part, "wb") { |file| file.write(download_payload) }
    {
      :final_url => "https://example.invalid/foundation.bin?private=test",
      :http_status => 200,
      :content_length => download_payload.bytesize,
      :bytes => download_payload.bytesize,
      :sha256 => download_hash,
      :headers => { "etag" => "foundation" }
    }
  end
  download_result = Reloaded::Download.fetch(
    "https://example.invalid/foundation.bin?private=test",
    download_target,
    :sha256 => download_hash,
    :expected_bytes => download_payload.bytesize,
    :retries => 1
  )
  check("Download API retries, verifies, and atomically promotes large files") do
    Reloaded::API.public?(:download) && Reloaded::API.available?(:download) &&
      download_result.success? && download_result.attempts == 2 &&
      download_result.bytes == download_payload.bytesize &&
      download_result.url == "https://example.invalid/foundation.bin" &&
      File.read(download_target) == download_payload &&
      !File.exist?("#{download_target}.part")
  end
  download_check_debug = $DEBUG
  $DEBUG = false
  invalid_download = Reloaded::Download.fetch(
    "https://example.invalid/foundation.bin",
    download_target,
    :sha256 => ("0" * 64),
    :retries => 0
  )
  $DEBUG = download_check_debug
  check("Download API rejects invalid payloads without replacing a valid destination") do
    invalid_download.error_code == :checksum_mismatch &&
      File.read(download_target) == download_payload &&
      !File.exist?("#{download_target}.part")
  end
  resume_target = File.join(download_test_root, "resume.bin")
  resume_payload = "foundation-resumable-download"
  resume_hash = Digest::SHA256.hexdigest(resume_payload)
  resume_split = 12
  resume_attempts = 0
  Reloaded::Download.transport_override = proc do |_url, part, options, _task|
    resume_attempts += 1
    if resume_attempts == 1
      File.open(part, "wb") { |file| file.write(resume_payload[0, resume_split]) }
      raise Reloaded::Download::Failure.new(:network_error, "Expected resumable interruption")
    end
    existing = File.file?(part) ? File.read(part) : ""
    raise "Partial download was not preserved." unless options[:resume] && existing == resume_payload[0, resume_split]
    File.open(part, "ab") { |file| file.write(resume_payload[resume_split, resume_payload.length]) }
    {
      :final_url => "https://example.invalid/resume.bin",
      :http_status => 206,
      :content_length => resume_payload.bytesize,
      :bytes => resume_payload.bytesize,
      :sha256 => resume_hash,
      :headers => { "accept-ranges" => "bytes" }
    }
  end
  resumed_download = Reloaded::Download.fetch(
    "https://example.invalid/resume.bin",
    resume_target,
    :sha256 => resume_hash,
    :expected_bytes => resume_payload.bytesize,
    :resume => true,
    :retries => 1
  )
  check("Download API resumes an opted-in partial file across retries") do
    resumed_download.success? && resumed_download.attempts == 2 &&
      File.read(resume_target) == resume_payload &&
      !File.exist?("#{resume_target}.part")
  end
  Reloaded::Download.transport_override = nil
  File.delete(download_target) if File.file?(download_target)
  File.delete(resume_target) if File.file?(resume_target)
  Dir.rmdir(download_test_root) if Dir.exist?(download_test_root) && Dir.entries(download_test_root).length == 2
  load File.join(RELOADED_ROOT, "Core", "Foundation", "Archive.rb")
  Reloaded::Settings.set("platform_override", "Windows", :persist => false)
  check("Archive API exposes the bundled Windows and Proton adapter") do
    Reloaded::API.public?(:archive) && Reloaded::API.available?(:archive) &&
      Reloaded::Archive.available? && File.file?(Reloaded::Platform.archive_tool_path)
  end
  archive_check_debug = $DEBUG
  $DEBUG = false
  archive_path_checks = begin
    absolute_archive_path = "C" + ":/outside.txt"
    Reloaded::Archive.send(:validate_entry_path!, "safe/folder/file.txt") == "safe/folder/file.txt" &&
      ["../outside.txt", absolute_archive_path, "NUL.txt"].all? do |path|
        begin
          Reloaded::Archive.send(:validate_entry_path!, path)
          false
        rescue Exception => e
          [:path_traversal, :unsafe_path].include?(e.respond_to?(:code) ? e.code : nil)
        end
      end
  end
  $DEBUG = archive_check_debug
  check("Archive API rejects traversal, absolute, and reserved entry paths") { archive_path_checks }
  load File.join(RELOADED_ROOT, "Core", "Foundation", "SpritePacks.rb")
  spritepack_check_root = File.join(RELOADED_ROOT, "Cache", "SpritePacks", "foundation_check_windows")
  spritepack_path = File.join(spritepack_check_root, "1.pak")
  Reloaded::SpritePacks.send(:ensure_directory, spritepack_check_root)
  spritepack_png = [137, 80, 78, 71, 13, 10, 26, 10].pack("C*") + "foundation-sprite"
  File.open(spritepack_path, "wb") do |file|
    file.write("SPAK")
    file.write([1].pack("V"))
    file.write([1, 0, 0, spritepack_png.length].pack("VVVV"))
    file.write(spritepack_png)
  end
  spritepack = Reloaded::SpritePacks::Pack.new(spritepack_path, 1)
  spritepack_data = spritepack.read(spritepack.entry(1, ""))
  check("Sprite Packs reads bounded AFI-compatible per-head entries") do
    Reloaded::API.public?(:sprite_packs) && Reloaded::API.available?(:sprite_packs) &&
      spritepack.entry_count == 1 && spritepack_data == spritepack_png
  end
  spritepack_layers = [
    { :id => "older", :sequence => 20260701000000, :created_at => "2026-07-01T00:00:00Z" },
    { :id => "newer", :sequence => 20260801000000, :created_at => "2026-08-01T00:00:00Z" }
  ]
  check("Sprite Packs orders monthly layers newest-first and honors Full cutoffs") do
    sorted = Reloaded::SpritePacks.send(:sort_update_layers, spritepack_layers)
    sorted.first[:id] == "newer" &&
      Reloaded::SpritePacks.send(:update_compacted?, "2026-07-01T00:00:00Z", "2026-07-15T00:00:00Z") &&
      !Reloaded::SpritePacks.send(:update_compacted?, "2026-08-01T00:00:00Z", "2026-07-15T00:00:00Z")
  end
  File.delete(spritepack_path) if File.file?(spritepack_path)
  Dir.rmdir(spritepack_check_root) if Dir.exist?(spritepack_check_root) && Dir.entries(spritepack_check_root).length == 2
  Reloaded::Settings.set("platform_override", "JoiPlay", :persist => false)
  check("JoiPlay keeps downloads and archive extraction unavailable") do
    !Reloaded::Platform.supports?(:downloads) && !Reloaded::Download.available? &&
      !Reloaded::Platform.supports?(:archive_extract) && !Reloaded::Archive.available?
  end
  Reloaded::Settings.set("platform_override", "Windows", :persist => false)
  load File.join(RELOADED_ROOT, "Core", "Foundation", "FileActions.rb")
  resolved_version = Reloaded::FileActions.resolve("Reloaded/Version.md", :type => :file)
  check("File Actions exposes the safe public API") do
    Reloaded::API.public?(:file_actions) && Reloaded::API.available?(:file_actions) &&
      [:open, :open_file, :open_folder, :copy, :read_clipboard, :export_file,
       :export_log, :export_file_async, :export_log_async, :resolve, :inside_game?, :display_path, :sanitize].all? do |method|
        Reloaded::FileActions.respond_to?(method)
      end
  end
  check("File Actions resolves files from the game root") do
    resolved_version == File.join(RELOADED_ROOT, "Version.md") &&
      Reloaded::FileActions.inside_game?(resolved_version, :must_exist => true)
  end
  outside_path = File.expand_path(File.join(GAME_ROOT, "..", "outside.txt"))
  path_check_debug = $DEBUG
  $DEBUG = false
  outside_blocked = begin
    Reloaded::FileActions.resolve(outside_path, :must_exist => false)
    false
  rescue
    true
  end
  $DEBUG = path_check_debug
  check("File Actions refuses paths outside the game root") { outside_blocked }
  check("File Actions never displays an outside absolute path") do
    Reloaded::FileActions.display_path(outside_path) == "outside.txt"
  end
  remote_check_debug = $DEBUG
  load File.join(RELOADED_ROOT, "Core", "Foundation", "RemoteData.rb")
  remote_test_root = File.join(RELOADED_ROOT, "Cache", "RemoteData", "foundation_check_windows")
  remote_cache = File.join(remote_test_root, "source.json")
  remote_local = File.join(remote_test_root, "local.json")
  Reloaded::RemoteData.send(:ensure_directory, remote_test_root)
  File.open(remote_local, "wb") { |file| file.write(JSON.generate({ "value" => "local" })) }
  Reloaded::Settings.set("platform_override", "Windows", :persist => false)
  Reloaded::RemoteData.register(
    :foundation_remote,
    :owner => :foundation_check,
    :format => :json,
    :url => "https://example.invalid/foundation.json",
    :cache_path => remote_cache,
    :local_path => remote_local,
    :retries => 0,
    :validator => proc { |value| value.is_a?(Hash) && !value["value"].to_s.empty? }
  )
  transport_responses = []
  transport_calls = 0
  Reloaded::RemoteData.transport_override = proc do |_url, _headers, _options|
    transport_calls += 1
    transport_responses.shift || {
      :status => 0, :error_code => :test_unavailable,
      :error_message => "Test transport has no response."
    }
  end
  transport_responses << {
    :status => 200,
    :body => JSON.generate({ "value" => "remote", "optional" => nil }),
    :headers => { "ETag" => "foundation-etag" }
  }
  fresh_remote = Reloaded::RemoteData.fetch(:foundation_remote, :force => true)
  check("Remote Data fetches, validates, and caches structured JSON") do
    Reloaded::API.public?(:remote_data) && Reloaded::API.available?(:remote_data) &&
      fresh_remote.ok? && fresh_remote.remote_confirmed? &&
      fresh_remote.source == :remote && fresh_remote.value["value"] == "remote" &&
      File.file?(remote_cache)
  end
  cached_before_invalid = File.read(remote_cache)
  transport_responses << { :status => 200, :body => "{invalid", :headers => {} }
  $DEBUG = false
  invalid_remote = Reloaded::RemoteData.fetch(:foundation_remote, :force => true)
  $DEBUG = remote_check_debug
  check("Invalid remote data preserves and returns the last-known-good cache") do
    invalid_remote.ok? && invalid_remote.fallback? && invalid_remote.source == :cache &&
      invalid_remote.value["value"] == "remote" && File.read(remote_cache) == cached_before_invalid
  end
  transport_responses << { :status => 304, :body => "", :headers => {} }
  unchanged_remote = Reloaded::RemoteData.fetch(:foundation_remote)
  check("Remote Data supports conditional not-modified responses") do
    unchanged_remote.ok? && unchanged_remote.remote_confirmed? &&
      unchanged_remote.status == :not_modified && unchanged_remote.source == :cache
  end
  exposed_remote = Reloaded::RemoteData.source(:foundation_remote)
  exposed_remote[:owner] = :changed
  check("Remote Data inspection cannot mutate source ownership") do
    Reloaded::RemoteData.source(:foundation_remote)[:owner] == :foundation_check
  end
  $DEBUG = false
  duplicate_remote_blocked = begin
    Reloaded::RemoteData.register(:foundation_remote, :owner => :other, :url => "https://example.invalid/other.json")
    false
  rescue
    true
  end
  $DEBUG = remote_check_debug
  check("Remote Data rejects duplicate source ownership") { duplicate_remote_blocked }
  $DEBUG = false
  remote_outside_blocked = begin
    Reloaded::RemoteData.register(
      :foundation_outside,
      :owner => :foundation_check,
      :url => "https://example.invalid/outside.json",
      :cache_path => outside_path
    )
    false
  rescue
    true
  end
  $DEBUG = remote_check_debug
  check("Remote Data refuses cache paths outside the game folder") { remote_outside_blocked }
  calls_before_joiplay = transport_calls
  Reloaded::Settings.set("platform_override", "JoiPlay", :persist => false)
  joiplay_remote = Reloaded::RemoteData.fetch(:foundation_remote, :force => true)
  check("JoiPlay uses cached Remote Data without attempting network access") do
    joiplay_remote.ok? && joiplay_remote.source == :cache && joiplay_remote.fallback? &&
      transport_calls == calls_before_joiplay
  end
  Reloaded::RemoteData.transport_override = nil
  Reloaded::RemoteData.clear(:foundation_remote)
  File.delete(remote_local) if File.file?(remote_local)
  Dir.rmdir(remote_test_root) if Dir.exist?(remote_test_root) && Dir.entries(remote_test_root).length == 2
  $DEBUG = remote_check_debug
  Reloaded::Settings.set("platform_override", "Windows", :persist => false)
  load File.join(RELOADED_ROOT, "Core", "Foundation", "TempCleanup.rb")
  cleanup_booted = Reloaded::TempCleanup.boot
  check("Temporary cleanup waits for module registrations before boot pruning") do
    cleanup_booted && Reloaded::Events.handlers(:modules_loaded).any? do |entry|
      entry[:id] == :cleanup_abandoned_reloaded_files
    end
  end
  cleanup_test_root = File.join(RELOADED_ROOT, "Cache", "TempCleanup", "foundation_check_windows")
  begin
    runtime_root = File.join(cleanup_test_root, "runtime")
    cache_root = File.join(cleanup_test_root, "remote")
    FileUtils.mkdir_p(runtime_root)
    FileUtils.mkdir_p(cache_root)
    old_time = Time.now - Reloaded::TempCleanup::ABANDONED_AGE - 60
    stale_part = File.join(runtime_root, "payload.zip.part")
    fresh_part = File.join(runtime_root, "active.zip.part")
    unknown_file = File.join(runtime_root, "keep.txt")
    stale_extract = File.join(runtime_root, "rld_install_100_200")
    FileUtils.mkdir_p(stale_extract)
    File.open(stale_part, "wb") { |file| file.write("old") }
    File.open(fresh_part, "wb") { |file| file.write("new") }
    File.open(unknown_file, "wb") { |file| file.write("keep") }
    extract_payload = File.join(stale_extract, "payload.txt")
    File.open(extract_payload, "wb") { |file| file.write("old") }
    File.utime(old_time, old_time, stale_part)
    File.utime(old_time, old_time, extract_payload)
    File.utime(old_time, old_time, stale_extract)
    cleanup_summary = Reloaded::TempCleanup.send(:new_summary)
    Reloaded::TempCleanup.send(:cleanup_runtime_root, runtime_root, Time.now, cleanup_summary)
    check("Temporary cleanup removes only abandoned recognized runtime files") do
      !File.exist?(stale_part) && !File.exist?(stale_extract) &&
        File.file?(fresh_part) && File.file?(unknown_file) &&
        cleanup_summary[:failures] == 0
    end

    protected_cache = File.join(cache_root, "protected.json")
    stale_cache = File.join(cache_root, "stale.json")
    recent_cache = File.join(cache_root, "recent.json")
    File.open(protected_cache, "wb") { |file| file.write("protected") }
    File.open(stale_cache, "wb") { |file| file.write("stale") }
    File.open(recent_cache, "wb") { |file| file.write("recent") }
    cache_old_time = Time.now - Reloaded::TempCleanup::REMOTE_CACHE_MAX_AGE - 60
    File.utime(cache_old_time, cache_old_time, protected_cache)
    File.utime(cache_old_time, cache_old_time, stale_cache)
    cache_summary = Reloaded::TempCleanup.send(:new_summary)
    Reloaded::TempCleanup.send(
      :prune_remote_cache, cache_root, [protected_cache], Time.now, cache_summary,
      Reloaded::TempCleanup::REMOTE_CACHE_MAX_AGE, 1_000_000
    )
    check("Temporary cleanup protects registered caches during age pruning") do
      File.file?(protected_cache) && !File.exist?(stale_cache) && File.file?(recent_cache)
    end

    File.open(protected_cache, "wb") { |file| file.write("p" * 20) }
    size_cache_a = File.join(cache_root, "size_a.json")
    size_cache_b = File.join(cache_root, "size_b.json")
    File.open(size_cache_a, "wb") { |file| file.write("a" * 12) }
    File.open(size_cache_b, "wb") { |file| file.write("b" * 12) }
    File.utime(Time.now - 120, Time.now - 120, size_cache_a)
    File.utime(Time.now - 60, Time.now - 60, size_cache_b)
    size_summary = Reloaded::TempCleanup.send(:new_summary)
    Reloaded::TempCleanup.send(
      :prune_remote_cache, cache_root, [protected_cache], Time.now, size_summary,
      Reloaded::TempCleanup::REMOTE_CACHE_MAX_AGE, 20
    )
    remaining_cache_bytes = Dir[File.join(cache_root, "*.json")].inject(0) do |total, path|
      total + File.size(path)
    end
    check("Temporary cleanup prunes oldest unregistered caches without crossing protected caches") do
      File.file?(protected_cache) && remaining_cache_bytes <= 20 && size_summary[:failures] == 0
    end
  ensure
    FileUtils.rm_rf(cleanup_test_root) if File.exist?(cleanup_test_root)
    cleanup_parent = File.dirname(cleanup_test_root)
    Dir.rmdir(cleanup_parent) if Dir.exist?(cleanup_parent) && Dir.entries(cleanup_parent).length == 2
  end
  task_check_debug = $DEBUG
  $DEBUG = false
  load File.join(RELOADED_ROOT, "Core", "Foundation", "Task.rb")
  task_main_thread = Thread.current
  worker_uses_main_thread_transport = nil
  Thread.new do
    worker_uses_main_thread_transport = Reloaded::RemoteData.send(:main_thread_transport?)
  end.join
  check("RemoteData avoids the engine-native HTTP transport on worker threads") do
    worker_uses_main_thread_transport == false
  end
  task_callback = nil
  successful_task = Reloaded::Task.start(
    :foundation_task,
    :owner => :foundation_check,
    :on_success => proc { |outcome| task_callback = [outcome.value, Thread.current == task_main_thread] }
  ) do |task|
    task.report(0.5, "Working")
    42
  end
  100.times do
    Reloaded::Task.update
    break if successful_task.complete?
    sleep(0.01)
  end
  check("Task delivers structured success callbacks on the main thread") do
    Reloaded::API.public?(:task) && Reloaded::API.available?(:task) &&
      successful_task.complete? && successful_task.outcome.success? &&
      successful_task.outcome.progress == 0.5 && task_callback == [42, true]
  end
  helper_task = Reloaded::Task.start(:foundation_progress_helpers) do |task|
    task.report_ratio(1, 4, "Quarter complete")
    sleep(0.05)
    task.indeterminate!("Waiting")
    sleep(0.05)
    :done
  end
  saw_ratio_progress = false
  saw_indeterminate_progress = false
  100.times do
    helper_snapshot = helper_task.snapshot
    saw_ratio_progress ||= helper_snapshot[:progress] == 0.25 && helper_snapshot[:stage] == "Quarter complete"
    saw_indeterminate_progress ||= helper_snapshot[:progress].nil? && helper_snapshot[:stage] == "Waiting"
    Reloaded::Task.update
    break if helper_task.complete? && saw_ratio_progress && saw_indeterminate_progress
    sleep(0.005)
  end
  check("Task exposes ratio and indeterminate progress helpers") do
    helper_task.complete? && saw_ratio_progress && saw_indeterminate_progress && !Reloaded::Task.updating?
  end
  Reloaded::PopupWindow.instance_variable_set(:@foundation_modal_active, true)
  Reloaded::PopupWindow.define_singleton_method(:modal_active?) do
    !!@foundation_modal_active
  end
  modal_callback = nil
  modal_task = Reloaded::Task.start(
    :foundation_modal_task,
    :on_success => proc { |outcome| modal_callback = outcome.value }
  ) { :delivered }
  100.times do
    Reloaded::Task.update
    break if modal_task.state == :ready
    sleep(0.01)
  end
  modal_deferred = modal_task.state == :ready && modal_callback.nil?
  Reloaded::PopupWindow.instance_variable_set(:@foundation_modal_active, false)
  Reloaded::Task.update
  check("Task defers completion while a shared modal is active") do
    modal_deferred && modal_task.complete? && modal_callback == :delivered
  end
  reused_task = Reloaded::Task.start(:foundation_reuse) { |task| task.checkpoint!; sleep(0.03); :first }
  same_task = Reloaded::Task.start(:foundation_reuse, :duplicate => :reuse) { :second }
  check("Task reuses duplicate work by key") { reused_task.id == same_task.id }
  100.times do
    Reloaded::Task.update
    break if reused_task.complete?
    sleep(0.01)
  end
  failed_task = Reloaded::Task.start(:foundation_failure) { raise "Expected task failure" }
  100.times do
    Reloaded::Task.update
    break if failed_task.complete?
    sleep(0.01)
  end
  check("Task isolates worker failures into outcomes") do
    failed_task.complete? && failed_task.outcome.failed? &&
      failed_task.outcome.error_code == :exception &&
      failed_task.outcome.error_message.include?("Expected task failure")
  end
  cancellable_task = Reloaded::Task.start(:foundation_cancel) do |task|
    100.times do
      sleep(0.005)
      task.checkpoint!
    end
    :late
  end
  cancellable_task.cancel
  100.times do
    Reloaded::Task.update
    break if cancellable_task.complete?
    sleep(0.01)
  end
  check("Task cancellation is cooperative and does not kill worker threads") do
    cancellable_task.complete? && cancellable_task.outcome.cancelled?
  end
  download_cancel_root = File.join(RELOADED_ROOT, "Cache", "Download", "foundation_cancel_check")
  download_cancel_target = File.join(download_cancel_root, "payload.bin")
  Reloaded::Download.send(:ensure_directory, download_cancel_root)
  File.open(download_cancel_target, "wb") { |file| file.write("valid-payload") }
  cancelled_download = false
  Reloaded::Download.transport_override = proc do |_url, part, _options, _task|
    File.open(part, "wb") { |file| file.write("partial-payload") }
    raise Reloaded::Task::Cancelled, "Expected cancellation"
  end
  begin
    Reloaded::Download.fetch(
      "https://example.invalid/foundation.bin",
      download_cancel_target,
      :retries => 0
    )
  rescue Reloaded::Task::Cancelled
    cancelled_download = true
  end
  check("Download API cancellation removes partial files without replacing the destination") do
    cancelled_download && File.read(download_cancel_target) == "valid-payload" &&
      !File.exist?("#{download_cancel_target}.part")
  end
  Reloaded::Download.transport_override = nil
  File.delete(download_cancel_target) if File.file?(download_cancel_target)
  Dir.rmdir(download_cancel_root) if Dir.exist?(download_cancel_root) && Dir.entries(download_cancel_root).length == 2
  Reloaded::Task.shutdown
  $DEBUG = task_check_debug
  load File.join(RELOADED_ROOT, "Core", "Foundation", "Rewards.rb")
  load File.join(RELOADED_ROOT, "Core", "Foundation", "RewardTypes.rb")
  reward_state = { :points => 0, :finalized => 0 }
  Reloaded::Rewards.register(
    :foundation_points,
    :owner => :foundation_check,
    :priority => 10,
    :aliases => [:foundation_score],
    :validate => proc { |reward, _context|
      reward[:quantity].to_i > 0 ? Reloaded::Rewards.success(:reward => reward) : Reloaded::Rewards.failure(:invalid_points, "Invalid points.")
    },
    :grant => proc { |reward, _context|
      before = reward_state[:points]
      reward_state[:points] += reward[:quantity].to_i
      Reloaded::Rewards.success(:reward => reward, :details => { :receipt_data => { :before => before } })
    },
    :rollback => proc { |receipt, _context|
      reward_state[:points] = receipt.data[:before]
      true
    },
    :finalize => proc { |_receipt, _context|
      reward_state[:finalized] += 1
      true
    }
  )
  Reloaded::Rewards.register(
    :foundation_reward_failure,
    :owner => :foundation_check,
    :priority => 20,
    :grant => proc { |_reward, _context| Reloaded::Rewards.failure(:expected_failure, "Expected failure.") }
  )
  normalized_reward = Reloaded::Rewards.normalize(:type => :foundation_score, :quantity => 3)
  check("Rewards registers owned types and compatibility aliases") do
    Reloaded::API.public?(:rewards) && Reloaded::API.available?(:rewards) &&
      normalized_reward[:type] == :foundation_points && normalized_reward[:quantity] == 3 &&
      Reloaded::Rewards.type(:foundation_points)[:owner] == :foundation_check
  end
  duplicate_reward = Reloaded::Rewards.register(:foundation_points, :owner => :other, :grant => proc { true })
  check("Rewards rejects duplicate type ownership") do
    duplicate_reward.nil? && Reloaded::Rewards.type(:foundation_points)[:owner] == :foundation_check
  end
  failed_reward_batch = Reloaded::Rewards.grant_all([
    { :type => :foundation_points, :quantity => 5 },
    { :type => :foundation_reward_failure, :quantity => 1 }
  ], :source => :foundation_check)
  check("Rewards rolls back an atomic batch after a grant failure") do
    !failed_reward_batch.ok? && reward_state[:points] == 0 && reward_state[:finalized] == 0
  end
  successful_reward_batch = Reloaded::Rewards.grant_all([
    { :type => :foundation_points, :quantity => 2 },
    { :type => :foundation_points, :quantity => 4 }
  ], :source => :foundation_check)
  reward_receipts = successful_reward_batch.details[:receipts]
  rolled_back_reward_batch = Reloaded::Rewards.rollback_all(reward_receipts, :source => :foundation_check)
  check("Rewards returns reversible receipts for successful batches") do
    successful_reward_batch.ok? && reward_receipts.length == 2 && rolled_back_reward_batch &&
      reward_state[:points] == 0 && reward_state[:finalized] == 2
  end
  deferred_reward_batch = Reloaded::Rewards.grant_all(
    [{ :type => :foundation_points, :quantity => 1 }],
    :source => :foundation_check,
    :defer_finalize => true
  )
  deferred_receipts = deferred_reward_batch.details[:receipts]
  deferred_before_finalize = reward_state[:finalized]
  deferred_finalized = Reloaded::Rewards.finalize_all(deferred_receipts, :source => :foundation_check)
  Reloaded::Rewards.rollback_all(deferred_receipts, :source => :foundation_check)
  check("Rewards supports deferred finalization for larger transactions") do
    deferred_reward_batch.ok? && deferred_before_finalize == 2 && deferred_finalized &&
      reward_state[:finalized] == 3 && reward_state[:points] == 0
  end
  exposed_reward_type = Reloaded::Rewards.type(:foundation_points)
  exposed_reward_type[:aliases] << :changed
  check("Reward type inspection cannot mutate the registry") do
    !Reloaded::Rewards.type(:foundation_points)[:aliases].include?(:changed)
  end
  check("Extended reward types are registered") do
    [:currency, :pokemon, :tm_vault, :outfit, :feature_unlock, :choice, :random].all? do |type|
      Reloaded::Rewards.registered?(type)
    end
  end
  currency_balance = 10
  Reloaded::Rewards.register_currency(
    :foundation_tokens,
    :owner => :foundation_check,
    :name => "Foundation Tokens",
    :getter => proc { currency_balance },
    :setter => proc { |value| currency_balance = value },
    :max => 99
  )
  currency_result = Reloaded::Rewards.grant(
    { :type => :currency, :currency => :foundation_tokens, :amount => 7 },
    :source => :foundation_check
  )
  currency_rolled_back = Reloaded::Rewards.rollback(currency_result.receipt, :source => :foundation_check)
  check("Currency rewards support registered balances and rollback") do
    currency_result.ok? && currency_rolled_back && currency_balance == 10
  end
  pokemon_stub_created = !defined?(Pokemon)
  if pokemon_stub_created
    Object.const_set(:Pokemon, Class.new do
      def type1; :NORMAL; end
      def type2; :NORMAL; end
      def types; [:NORMAL]; end
    end)
  end
  Reloaded::Rewards.send(:install_pokemon_typing_patch)
  typed_pokemon = Pokemon.new
  typed_pokemon.reloaded_reward_types = [:FIRE, :WATER]
  check("Reward Pokemon typings override all native type readers") do
    typed_pokemon.type1 == :FIRE && typed_pokemon.type2 == :WATER && typed_pokemon.types == [:FIRE, :WATER]
  end
  Object.send(:remove_const, :Pokemon) if pokemon_stub_created
  composite_before = reward_state[:finalized]
  choice_result = Reloaded::Rewards.grant(
    {
      :type => :choice,
      :options => [
        { :type => :foundation_points, :quantity => 2 },
        { :type => :foundation_points, :quantity => 5 }
      ]
    },
    :source => :foundation_check,
    :choice_selector => proc { |_parent, _options| 1 }
  )
  choice_revealed = Reloaded::Rewards.revealed_rewards([choice_result.receipt])
  choice_rolled_back = Reloaded::Rewards.rollback(choice_result.receipt, :source => :foundation_check)
  check("Choice rewards grant, reveal, and roll back the selected reward") do
    choice_result.ok? && choice_revealed.length == 1 && choice_revealed[0][:quantity] == 5 &&
      choice_rolled_back && reward_state[:points] == 0 && reward_state[:finalized] == composite_before + 1
  end
  random_result = Reloaded::Rewards.grant(
    {
      :type => :random,
      :rewards => [
        { :type => :foundation_points, :quantity => 3, :weight => 1 },
        { :type => :foundation_points, :quantity => 8, :weight => 1 }
      ]
    },
    :source => :foundation_check,
    :random_roll => 0
  )
  random_revealed = Reloaded::Rewards.revealed_rewards([random_result.receipt])
  random_rolled_back = Reloaded::Rewards.rollback(random_result.receipt, :source => :foundation_check)
  check("Random rewards use weighted leaf grants with reversible receipts") do
    random_result.ok? && random_revealed.length == 1 && random_revealed[0][:quantity] == 3 &&
      random_rolled_back && reward_state[:points] == 0
  end
  percentage_result = Reloaded::Rewards.grant(
    {
      :type => :random,
      :rewards => [
        { :type => :foundation_points, :quantity => 3, :chance => 25 },
        { :type => :foundation_points, :quantity => 8, :chance => 75 }
      ]
    },
    :source => :foundation_check,
    :random_roll => 25
  )
  percentage_revealed = Reloaded::Rewards.revealed_rewards([percentage_result.receipt])
  percentage_rolled_back = Reloaded::Rewards.rollback(percentage_result.receipt, :source => :foundation_check)
  invalid_percentage = Reloaded::Rewards.validate(
    {
      :type => :random,
      :rewards => [
        { :type => :foundation_points, :quantity => 1, :chance => 40 },
        { :type => :foundation_points, :quantity => 1, :chance => 50 }
      ]
    },
    :source => :foundation_check
  )
  check("Random rewards support percentages totaling exactly 100") do
    percentage_result.ok? && percentage_revealed[0][:quantity] == 8 && percentage_rolled_back &&
      reward_state[:points] == 0 && !invalid_percentage.ok? && invalid_percentage.code == :invalid_percentage_total
  end
  removed_probability = Reloaded::Rewards.validate(
    {
      :type => :random,
      :rewards => [
        { :type => :foundation_points, :quantity => 1, :probability => 100 }
      ]
    },
    :source => :foundation_check
  )
  check("Random rewards reject removed probability and percent fields") do
    !removed_probability.ok? && removed_probability.code == :unsupported_random_chance_field
  end
  pokevial_reward_source = File.read(File.join(RELOADED_ROOT, "Modules", "PokeVial.rb"))
  iv_reward_source = File.read(File.join(RELOADED_ROOT, "Modules", "IVBoundaries.rb"))
  mart_reward_source = File.read(File.join(RELOADED_ROOT, "Modules", "ReloadedMart", "Backend.rb"))
  daily_featured_source = File.read(File.join(RELOADED_ROOT, "Modules", "ReloadedMart", "Automation", "DailyFeatured.rb"))
  economy_event_source = File.read(File.join(RELOADED_ROOT, "Modules", "ReloadedMart", "Automation", "EconomyEvents.rb"))
  check("Reloaded reward adapters use the shared registry") do
    pokevial_reward_source.include?("register_reward_handlers") &&
      pokevial_reward_source.include?(":pokevial_charge") &&
      iv_reward_source.include?(":iv_boundary_boost") &&
      mart_reward_source.include?("Reloaded::Rewards.validate_all") &&
      mart_reward_source.include?("Reloaded::Rewards.grant_all")
  end
  mart_editor_source = File.read(File.join(GAME_ROOT, "Admin Tools", "Reloaded Mart Editor", "ReloadedMartEditor.rb"))
  reward_types_source = File.read(File.join(RELOADED_ROOT, "Core", "Foundation", "RewardTypes.rb"))
  economy_event_editor_source = File.read(File.join(GAME_ROOT, "Admin Tools", "Reloaded Mart Editor", "EconomyEventEditor.rb"))
  economy_automation_path = File.join(RELOADED_ROOT, "Modules", "ReloadedMart", "Data", "AutomatedEvents.json")
  economy_automation_data = JSON.parse(File.read(economy_automation_path))
  economy_event_library_path = File.join(GAME_ROOT, "Admin Tools", "Reloaded Mart Editor", "EconomyEventLibrary.json")
  economy_event_library = JSON.parse(File.read(economy_event_library_path))
  economy_template_definition_block = economy_event_editor_source[/ECONOMY_BUILT_IN_TEMPLATE_DEFINITIONS = \[(.*?)\]\.freeze/m, 1].to_s
  economy_template_definition_count = economy_template_definition_block.scan(/^\s+\["[a-z0-9_]+", "/).length
  economy_template_item_counts = economy_template_definition_block.scan(/%w\[([A-Z0-9_\s]+)\]\]/).map { |items| items[0].split.length }
  check("Reloaded Mart enforces active entries, real unlocks, and nested reward dependencies") do
    mart_reward_source.include?("class UnlockEntryHandler") &&
      mart_reward_source.include?("def set_unlocked") &&
      mart_reward_source.include?("return fail_result(:inactive") &&
      mart_reward_source.include?("def required_reward_items") &&
      mart_reward_source.include?("daily_featured_modifier(entry, context) if daily_featured?(entry, context)") &&
      mart_reward_source.include?("Array(context[:activated_unlocks]).reverse_each")
  end
  check("Daily Featured owns its automation policy and deterministic Eastern schedule") do
    daily_featured_source.include?("DEFAULT_OFFER_COUNT = 3") &&
      daily_featured_source.include?("MINIMUM_DISCOUNT = 0") &&
      daily_featured_source.include?("STANDARD_DISCOUNT_MAXIMUM = 39") &&
      daily_featured_source.include?("HIGH_DISCOUNT_MINIMUM = 40") &&
      daily_featured_source.include?("MAXIMUM_DISCOUNT = 100") &&
      daily_featured_source.include?("DEFAULT_MINIMUM_DISCOUNT = 5") &&
      daily_featured_source.include?("DEFAULT_MAXIMUM_DISCOUNT = 50") &&
      daily_featured_source.include?("DEFAULT_HIGH_DISCOUNT_LIMIT = 1") &&
      daily_featured_source.include?("REPEAT_BLOCK_DAYS = 3") &&
      daily_featured_source.include?("ADDED_ITEM_ALLOWLIST") &&
      daily_featured_source.include?("TRUSTED_CLOCK_STATE_KEY") &&
      daily_featured_source.include?("def eastern_time") &&
      daily_featured_source.include?("def record_trusted_server_time") &&
      daily_featured_source.include?("def trusted_time") &&
      daily_featured_source.include?("Process::CLOCK_MONOTONIC") &&
      daily_featured_source.include?("def mod_added_item_ids") &&
      daily_featured_source.include?("def added_item_allowlist") &&
      daily_featured_source.include?("def compiled_base_item_ids") &&
      daily_featured_source.include?("def high_discount_item_ids") &&
      daily_featured_source.include?("patch[:operation].to_s == \"add\"") &&
      daily_featured_source.include?("def preview") &&
      mart_reward_source.include?("record_trusted_server_time(remote.server_time)") &&
      !mart_reward_source.include?("!Economy.automation_enabled?(\"restocks\")") &&
      !mart_reward_source.include?("return [] unless automation_enabled?(\"profile_tuning\")")
  end
  check("Economy Events validates cycle anchors without the optional Date library") do
    economy_event_source.include?("def parse_cycle_date") &&
      economy_event_source.include?("Time.utc(year, month, day)") &&
      economy_event_source.include?("!parse_cycle_date((value || DEFAULT_CYCLE_ANCHOR).to_s).nil?") &&
      !economy_event_source.include?("Date.parse((value || DEFAULT_CYCLE_ANCHOR).to_s)") &&
      economy_event_editor_source.include?("when :cycle_anchor then edit_economy_cycle_anchor(config)")
  end
  check("Reloaded Mart Editor targets schema 2 and exposes registered reward workflows and simplified navigation") do
    mart_editor_source.include?("ReloadedMart::SCHEMA_VERSION) ? ReloadedMart::SCHEMA_VERSION : 2") &&
      mart_editor_source.include?("\"pokevial_max_uses\"") &&
      mart_editor_source.include?("\"iv_boundary_boost\"") &&
      mart_editor_source.include?("\"feature_unlock\"") &&
      mart_editor_source.include?("\"choice\"") &&
      mart_editor_source.include?("\"random\"") &&
      mart_editor_source.include?("\"unlock_key\"") &&
      mart_editor_source.include?("\"Automation & Events\"") &&
      mart_editor_source.include?("\"Test & Publish\"") &&
      mart_editor_source.include?("def automation_events_rows") &&
      mart_editor_source.include?("\"Preview Today\"") &&
      mart_editor_source.include?("\"high_discount_limit\"") &&
      mart_editor_source.include?("when \"stock\"") &&
      mart_editor_source.include?("key.to_s == \"stock\"") &&
      daily_featured_source.include?("quantity > 0 ? quantity : nil") &&
      !mart_editor_source.include?("section_row(\"events\", \"Profile Tuning\"") &&
      !mart_editor_source.include?("\"Master OFF/ON switch for Reloaded Mart automation.\"") &&
      mart_editor_source.include?("def content_kind_rows") &&
      mart_editor_source.include?("\"Featured Items\"") &&
      mart_editor_source.include?("def featured_item_entry?") &&
      mart_editor_source.include?("@navigation_stack") &&
      mart_editor_source.include?("LIST_Y = Reloaded::ModManagerUI::LIST_Y") &&
      !mart_editor_source.include?("\"Filter Content\"") &&
      mart_editor_source.include?("@scope[:source] != :category") &&
      mart_editor_source.include?("EVENT_LIBRARY_FILE = File.join(TOOL_DIR, \"EconomyEventLibrary.json\")") &&
      mart_editor_source.include?("def load_economy_support_files") &&
      mart_editor_source.include?("def save_economy_support_files") &&
      economy_event_editor_source.include?("def open_economy_event_templates_editor") &&
      economy_event_editor_source.include?("def copy_economy_template_to_destination") &&
      economy_event_editor_source.include?(":automated, :curated, :themed") &&
      economy_event_editor_source.include?("def built_in_economy_event_templates") &&
      economy_template_definition_count == 18 &&
      economy_template_item_counts.length == 18 &&
      economy_template_item_counts.all? { |count| count >= 10 && count <= 15 } &&
      Array(economy_event_library["templates"]).length == 18
  end
  check("Reloaded Mart Pokemon rewards use guided sources and native defaults") do
    mart_editor_source.include?("def pokemon_species_mode_choices") &&
      mart_editor_source.include?("def pick_pokemon_form") &&
      mart_editor_source.include?("def difficulty_choices") &&
      mart_editor_source.include?("Random by Type") &&
      mart_editor_source.include?("Random by BST") &&
      mart_editor_source.include?("Use Level Moves") &&
      mart_editor_source.include?("Player / Native Default") &&
      reward_types_source.include?("def resolve_reward_species") &&
      reward_types_source.include?("def reward_species_candidates") &&
      reward_types_source.include?("reward[:generate_moves]") &&
      reward_types_source.include?("pokemon.reset_moves") &&
      reward_types_source.include?('B#{body.id_number}H#{head.id_number}')
  end
  check("Reloaded Mart Editor owns release versions and omits removed economy systems") do
    mart_editor_source.include?("def apply_automatic_versions") &&
      mart_editor_source.include?("def synchronize_entry_versions!") &&
      mart_editor_source.include?("def next_catalog_version") &&
      mart_editor_source.include?("Managed automatically when this entry's content changes.") &&
      mart_editor_source.include?("REMOVED_CATALOG_KEYS = %w[profile_tuning promo_codes]") &&
      !mart_editor_source.include?("def promotions_economy_rows") &&
      !mart_reward_source.include?("def profile_tuning") &&
      !economy_event_source.include?("profile_tuning(context)")
  end
  mart_publish_source = File.read(File.join(GAME_ROOT, "Admin Tools", "Reloaded Mart Editor", "PublishReloadedMart.bat"))
  check("Reloaded Mart publishing excludes editor-only catalog data") do
    mart_editor_source.include?("economy_events economy_event_templates economy_event_automation") &&
      mart_editor_source.include?("EDITOR_ONLY_NESTED_KEYS = %w[internal_notes]") &&
      mart_editor_source.include?("def online_catalog_data") &&
      mart_editor_source.include?("EDITOR_ONLY_CATALOG_KEYS.each { |key| payload.delete(key) }") &&
      mart_editor_source.include?("active_publishable_economy_event") &&
      economy_event_editor_source.include?("def active_publishable_economy_event") &&
      mart_editor_source.include?("name.start_with?(\"__\")") &&
      mart_editor_source.include?("export_online_json(false, false)") &&
      mart_publish_source.include?("set \"CATALOG_FILE=%ONLINE_FILE%\"") &&
      !mart_publish_source.include?("copy /Y \"%CATALOG_FILE%\" \"%ONLINE_FILE%\"")
  end
  check("Automated Economy Events use the shipped local pool and remain offline-capable") do
    File.file?(economy_automation_path) &&
      economy_event_source.include?("LOCAL_AUTOMATION_FILE") &&
      economy_event_source.include?("def load_local_automation") &&
      economy_event_source.include?("result.concat(manual_events) if online_available?") &&
      economy_event_source.include?("generated = generated_event(context)") &&
      economy_event_source.include?("MAX_AUTOMATED_PERCENT = 50") &&
      economy_automation_data["enabled"] == true &&
      Array(economy_automation_data["templates"]).length > 0 &&
      Array(economy_automation_data["templates"]).all? do |template|
        template.is_a?(Hash) &&
          !template.key?("internal_notes") &&
          Array(template["temporary_entries"]).length.between?(10, 15)
      end
  end
  mart_ui_source = File.read(File.join(RELOADED_ROOT, "Modules", "ReloadedMart", "UI.rb"))
  check("Reloaded Mart supports trusted editor previews and open-time online refresh") do
    mart_reward_source.include?(":admin_editor_preview") &&
      mart_reward_source.include?("def curated_available?") &&
      mart_reward_source.include?("def refreshing?") &&
      mart_reward_source.include?(":status => :success, :remote => outcome.value") &&
      mart_reward_source.include?("apply_remote_result(completion[:remote])") &&
      mart_ui_source.include?("def open_mart_actions") &&
      mart_ui_source.include?('View Event: #{event_label}') &&
      mart_ui_source.include?(":start_id => :view_event") &&
      !mart_ui_source.include?(":id => :refresh") &&
      !mart_ui_source.include?("def request_catalog_refresh") &&
      mart_ui_source.include?("def draw_economy_event_toast") &&
      mart_ui_source.include?('"#{values.max}% OFF"') &&
      mart_ui_source.include?("item_ids.shuffle.first(2)") &&
      mart_ui_source.include?("icon_size = 90") &&
      mart_ui_source.include?(":ok_text_offset_y => -7") &&
      mart_ui_source.include?("Displayed Economy Event id=") &&
      mart_ui_source.include?("Input.trigger?(Input::SPECIAL)") &&
      mart_ui_source.include?("Reloaded::HintText.special(\"Actions\")") &&
      !mart_ui_source.include?("pbPromptPromoCode") &&
      !mart_reward_source.include?("def redeem_promo_code")
  end
  check("Reloaded Mart validates remote catalogs on the main thread only") do
    !mart_reward_source.include?("source: :online_validation") &&
      mart_reward_source.include?("Catalog.load(raw, source: :online_fresh)") &&
      mart_reward_source.include?("RemoteData validators run on the worker thread") &&
      mart_reward_source.include?("registered?(REMOTE_SOURCE_ID)") &&
      mart_reward_source.include?("version > 0 && version <= SCHEMA_VERSION && entries.is_a?(Array)")
  end
  base_mart_catalog = JSON.parse(File.read(File.join(RELOADED_ROOT, "ReloadedMartBase.json")))
  check("Reloaded Mart ships editable offline stock that fresh online data replaces") do
    base_mart_catalog["schema_version"].to_i == 2 &&
      !base_mart_catalog.key?("profile_tuning") &&
      Array(base_mart_catalog["entries"]).length >= 10 &&
      mart_reward_source.include?("BASE_CATALOG_RELATIVE_PATH") &&
      mart_reward_source.include?("def load_base_catalog") &&
      mart_reward_source.include?("source.to_sym == :offline_base ? :offline_allowed : :fresh_required") &&
      mart_reward_source.include?("unless remote.remote_confirmed?") &&
      mart_reward_source.include?("Mart catalog ignored unconfirmed RemoteData cache") &&
      mart_editor_source.include?("BASE_CATALOG_FILE") &&
      mart_editor_source.include?('Catalog Source: #{catalog_target_label}') &&
      mart_editor_source.include?("def choose_catalog_target") &&
      mart_editor_source.include?("cannot be published as the online catalog")
  end
  check("Reloaded Mart banners, descriptions, stock, and restock text use no-shadow rendering") do
    mart_ui_source.include?("def no_shadow_text") &&
      mart_ui_source.include?("no_shadow_text(bitmap, x, 6, width, 16, banner, GOLD)") &&
      mart_ui_source.include?("no_shadow_text(bitmap, x, y, width, 18, line, color)") &&
      mart_ui_source.include?("no_shadow_text(bitmap, x, INFO_H - 20") &&
      mart_ui_source.include?("no_shadow_text(bitmap, 0, y, x + width, 15, \"Stock:") &&
      mart_ui_source.include?("no_shadow_text(bitmap, x, y, width, 15, heading, WHITE)") &&
      mart_ui_source.include?("no_shadow_text(bitmap, x + 6, y, item_w, 14") &&
      mart_ui_source.include?("no_shadow_text(bitmap, owned_x, y, 92, 14, \"Owned:") &&
      mart_ui_source.include?("no_shadow_text(bitmap, PAD, 4, icon_x - PAD * 2 - 4")
  end
  check("Reward bag limits use the game setting and bundles avoid linear quantity scans") do
    reward_source = File.read(File.join(RELOADED_ROOT, "Core", "Foundation", "Rewards.rb"))
    reward_source.include?("::Settings::BAG_MAX_PER_SLOT") &&
      mart_ui_source.include?("highest_storable_quantity") &&
      !mart_ui_source.include?("max.downto(1)")
  end
  $DEBUG = original_debug

  load File.join(RELOADED_ROOT, "Core", "Foundation", "Systems.rb")
  load File.join(RELOADED_ROOT, "Core", "Foundation", "Features.rb")
  check("System registry describes itself for dependent systems") do
    Reloaded::Systems.active?(:systems) && Reloaded::Systems.active?(:features)
  end
  Reloaded::Systems.register(:foundation_registry_base, :name => "Registry Base")
  Reloaded::Systems.register(
    :foundation_registry_child,
    :required_systems => [:foundation_registry_base]
  )
  check("System registry resolves required dependencies") do
    Reloaded::Systems.active?(:foundation_registry_base) &&
      Reloaded::Systems.active?(:foundation_registry_child)
  end
  Reloaded::Systems.register(:foundation_cycle_a, :required_systems => [:foundation_cycle_b])
  Reloaded::Systems.register(:foundation_cycle_b, :required_systems => [:foundation_cycle_a])
  check("System registry detects dependency cycles") do
    !Reloaded::Systems.available?(:foundation_cycle_a) &&
      Reloaded::Systems.reason(:foundation_cycle_a).include?("unavailable")
  end
  exposed_system = Reloaded::Systems.system(:foundation_registry_child)
  exposed_system[:required_systems] << :changed
  check("System inspection cannot mutate the registry") do
    !Reloaded::Systems.dependencies(:foundation_registry_child)[:required].include?(:changed)
  end
  Reloaded::Features.register(
    :foundation_experimental,
    :default => false,
    :classification => :experimental,
    :required_systems => [:foundation_registry_base]
  )
  initially_disabled = !Reloaded::Features.active?(:foundation_experimental)
  enabled_for_session = Reloaded::Features.enable(:foundation_experimental, :scope => :session)
  Reloaded::Features.reset(:foundation_experimental, :scope => :session)
  check("Feature session overrides respect declared defaults") do
    initially_disabled && enabled_for_session && !Reloaded::Features.active?(:foundation_experimental)
  end
  exposed_feature = Reloaded::Features.feature(:foundation_experimental)
  exposed_feature[:required_systems] << :changed
  check("Feature inspection cannot mutate the registry") do
    !Reloaded::Features.feature(:foundation_experimental)[:required_systems].include?(:changed)
  end
  load File.join(RELOADED_ROOT, "Core", "Modding", "ModManager.rb")
  feature_errors = []
  feature_candidate = { :required_features => ["missing_foundation_feature"], :system_tags => [] }
  Reloaded::ModManager.send(:validate_required_features, feature_candidate, feature_errors)
  check("Mod manifests reject missing required features") do
    feature_errors.any? { |message| message.include?("missing_foundation_feature") } &&
      feature_candidate[:system_tags].include?("missing_dependency")
  end

  Reloaded::Events.define(
    :foundation_contract_event,
    :required_context => [:value],
    :optional_context => [:label]
  )
  exposed_contract = Reloaded::Events.contract(:foundation_contract_event)
  exposed_contract[:required_context] << :changed
  check("Event contract inspection cannot mutate contracts") do
    Reloaded::Events.contract(:foundation_contract_event)[:required_context] == [:value]
  end
  Reloaded::Features.register(:foundation_event_gate, :default => false)
  gated_calls = 0
  Reloaded::Events.on(
    :foundation_contract_event,
    :foundation_gated_handler,
    :requires => { :features => [:foundation_event_gate] }
  ) { |_context| gated_calls += 1 }
  skipped_count = Reloaded::Events.emit(:foundation_contract_event, :value => 1)
  Reloaded::Features.enable(:foundation_event_gate, :scope => :session)
  called_count = Reloaded::Events.emit(:foundation_contract_event, :value => 2)
  check("Event handler requirements gate execution") do
    skipped_count == 0 && called_count == 1 && gated_calls == 1
  end
  Reloaded::Events.on(:foundation_undocumented_event, :foundation_unknown_handler) { |_context| nil }
  check("Event validation reports undocumented handlers") do
    Reloaded::Events.validate.any? do |finding|
      finding[:code] == :undocumented_event && finding[:event] == :foundation_undocumented_event
    end
  end
  failing_calls = 0
  Reloaded::Events.define(:foundation_failing_event)
  Reloaded::Events.on(:foundation_failing_event, :foundation_failing_handler) do |_context|
    failing_calls += 1
    raise "intentional event handler failure"
  end
  4.times { Reloaded::Events.emit(:foundation_failing_event) }
  disabled = Reloaded::Events.disabled_handlers.find do |entry|
    entry[:event] == :foundation_failing_event && entry[:id] == :foundation_failing_handler
  end
  check("Repeated event handler failures disable only that handler") do
    failing_calls == Reloaded::Events::FAILURE_LIMIT &&
      disabled && disabled[:failures] == Reloaded::Events::FAILURE_LIMIT
  end
  Reloaded::Events.on(:foundation_failing_event, :foundation_failing_handler) { |_context| nil }
  check("Re-registering an event handler clears its failure state") do
    Reloaded::Events.disabled_handlers.none? do |entry|
      entry[:event] == :foundation_failing_event && entry[:id] == :foundation_failing_handler
    end
  end

  load File.join(RELOADED_ROOT, "Core", "Foundation", "Validation.rb")
  check("Validation system resolves its registry dependency") do
    Reloaded::Systems.active?(:validation)
  end
  Reloaded::Validation.register(:foundation_normal_validator, :phase => :developer) do
    { :severity => :warning, :code => :foundation_warning, :message => "Foundation validation warning." }
  end
  normal_findings = Reloaded::Validation.run_check(:foundation_normal_validator)
  check("Validation normalizes registered findings") do
    normal_findings.length == 1 &&
      normal_findings[0][:severity] == :warning &&
      normal_findings[0][:check] == :foundation_normal_validator
  end
  broken_calls = 0
  Reloaded::Validation.register(:foundation_broken_validator, :phase => :developer) do
    broken_calls += 1
    raise "intentional foundation validator failure"
  end
  first_failure = Reloaded::Validation.run_check(:foundation_broken_validator)
  Reloaded::Validation.run_check(:foundation_broken_validator)
  check("Broken validators are isolated and disabled") do
    broken_calls == 1 &&
      first_failure.any? { |finding| finding[:code] == :validator_failed } &&
      Reloaded::Validation.summary[:disabled_checks] >= 1
  end


  load File.join(RELOADED_ROOT, "Core", "Foundation", "SaveMigrations.rb")
  migration_result = Reloaded::SaveMigrations.migrate(
    { :schema_version => 0, :systems => {}, :mods => {}, :metadata => {} },
    1
  )
  check("Reloaded save migrations run sequentially") do
    migration_result[:status] == :migrated &&
      migration_result[:bucket][:schema_version] == 1 &&
      migration_result[:applied] == ["reloaded_schema_0_to_1"]
  end
  Reloaded::SaveMigrations.register_mod(:foundation_check, :from => 0, :to => 1) do |data|
    data["migrated"] = true
    data
  end
  mod_migration_result = Reloaded::SaveMigrations.migrate(
    {
      :schema_version => 1,
      :systems => {},
      :mods => { "foundation_check" => { "value" => 1 } },
      :metadata => {}
    },
    1
  )
  check("Mod save migrations are namespaced") do
    mod_data = mod_migration_result[:bucket][:mods]["foundation_check"]
    mod_data["migrated"] == true && mod_data["_schema_version"] == 1
  end

  load File.join(RELOADED_ROOT, "Core", "Foundation", "SaveData.rb")
  original_bucket = {
    :schema_version => 1,
    :systems => {},
    :mods => {},
    :metadata => {
      "created_at" => "2020-01-02 03:04:05",
      "created_with_version" => "0.1.0",
      "custom_scalar" => "preserved"
    }
  }
  Reloaded::SaveData.load(original_bucket)
  Reloaded::SaveData.refresh_metadata!
  check("Save metadata preserves creation fields and scalar values") do
    Reloaded::SaveData.metadata_value(:created_at) == "2020-01-02 03:04:05" &&
      Reloaded::SaveData.created_with_version == "0.1.0" &&
      Reloaded::SaveData.metadata_value(:custom_scalar) == "preserved"
  end
  exposed_metadata = Reloaded::SaveData.metadata
  exposed_metadata["platform"] = "Changed"
  check("Save metadata inspection cannot mutate stored metadata") do
    Reloaded::SaveData.metadata_value(:platform) != "Changed"
  end
  check("Save metadata contains current diagnostic fields") do
    Reloaded::SaveData.last_saved_with_version == Reloaded::Versioning.current &&
      Reloaded::SaveData.metadata_value(:base_version) == Reloaded::Versioning.base &&
      Reloaded::SaveData.metadata_value(:enabled_mods).is_a?(Array)
  end
  Reloaded::Features.enable(:foundation_experimental, :scope => :save)
  check("Per-save feature overrides use Reloaded save data") do
    Reloaded::Features.active?(:foundation_experimental) &&
      Reloaded::SaveData.get(:features, :foundation_experimental, nil, :section => :systems) == true
  end
  newer_bucket = {
    :schema_version => Reloaded::SaveData::SCHEMA_VERSION + 1,
    :systems => { "future" => { "value" => 7 } },
    :mods => {},
    :metadata => { "future_value" => "preserve" }
  }
  Reloaded::SaveData.load(newer_bucket)
  preserved_bucket = Reloaded::SaveData.dump
  check("Newer Reloaded schemas are write-protected") do
    Reloaded::SaveData.write_blocked? &&
      Reloaded::SaveData.write_block_reason == :newer_schema &&
      preserved_bucket == newer_bucket
  end

  require "tmpdir"
  require "fileutils"
  module ::SaveData
    class << self
      attr_accessor :foundation_check_payload
      def compile_save_hash
        @foundation_check_payload || {}
      end
    end
  end unless defined?(::SaveData)
  load File.join(RELOADED_ROOT, "Core", "Foundation", "SaveProtection.rb")
  test_root = Dir.mktmpdir("hoenn_reloaded_foundation_")
  begin
    target = File.join(test_root, "File A.rxdata")
    ::SaveData.foundation_check_payload = { :value => 1 }
    ::SaveData.save_to_file(target)
    ::SaveData.foundation_check_payload = { :value => 2 }
    ::SaveData.save_to_file(target)
    check("Protected save replacement writes the complete new payload") do
      File.open(target, "rb") { |file| Marshal.load(file) } == { :value => 2 } &&
        !File.exist?("#{target}.reloaded.tmp") &&
        !File.exist?("#{target}.reloaded.previous")
    end
    migration_target = File.join(test_root, "File Migration.rxdata")
    migration_bucket = { :schema_version => 0, :systems => {}, :mods => {}, :metadata => {} }
    migration_save = { :reloaded => migration_bucket }
    File.open(migration_target, "wb") { |file| Marshal.dump(migration_save, file) }
    Reloaded::SaveProtection.track_save_source(migration_save, migration_target)
    migration_backup = Reloaded::SaveProtection.backup_before_migration(migration_bucket, :from => 0, :to => 1)
    migration_backup_root = File.join(test_root, "backups", "File_Migration")
    migration_backups = Dir.entries(migration_backup_root).select { |name| name.downcase.end_with?(".rxdata") }
    check("Reloaded migrations create a verified source-slot backup first") do
      migration_backup[:status] == :created && migration_backups.length == 1
    end
    12.times { Reloaded::SaveProtection.backup_savefile(target, "File A") }
    backup_root = File.join(test_root, "backups", "File_A")
    backups = Dir.entries(backup_root).select { |name| name.downcase.end_with?(".rxdata") }
    check("Rolling save backups retain the newest ten per slot") { backups.length == 10 }
  ensure
    FileUtils.remove_entry(test_root) if File.exist?(test_root)
  end
end

puts
if FAILURES.empty?
  puts "All foundation checks passed."
  exit 0
end
puts "#{FAILURES.length} foundation check(s) failed:"
FAILURES.each { |failure| puts "  - #{failure}" }
exit 1
