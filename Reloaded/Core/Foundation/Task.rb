#======================================================
# Reloaded Background Tasks
# Author: Stonewall
#======================================================
# Runs blocking work away from the game loop and delivers all callbacks on the
# main thread. Worker blocks must only perform I/O or computation; game state,
# UI, clipboard, and scene changes belong in completion callbacks.
#======================================================

begin
  require "thread"
rescue Exception
end

module Reloaded
  module Task
    DEFAULT_HISTORY_LIMIT = 24
    TERMINAL_STATES = [:succeeded, :failed, :cancelled, :timed_out, :rejected].freeze
    DUPLICATE_POLICIES = [:reuse, :reject, :queue].freeze

    class Cancelled < StandardError; end

    class Failed < StandardError
      attr_reader :code

      def initialize(message, code = :failed)
        @code = code.to_sym rescue :failed
        super(message.to_s)
      end
    end

    class Outcome
      attr_reader :id, :key, :owner, :state, :value, :error_code,
                  :error_message, :started_at, :finished_at, :duration,
                  :progress, :stage

      def initialize(values = {})
        @id = values[:id]
        @key = values[:key]
        @owner = values[:owner]
        @state = values[:state]
        @value = values[:value]
        @error_code = values[:error_code]
        @error_message = values[:error_message].to_s
        @started_at = values[:started_at]
        @finished_at = values[:finished_at]
        @duration = values[:duration].to_f
        @progress = values[:progress]
        @stage = values[:stage].to_s
      end

      def success?
        @state == :succeeded
      end

      def failed?
        @state == :failed || @state == :timed_out || @state == :rejected
      end

      def cancelled?
        @state == :cancelled
      end
    end

    class Handle
      def initialize(task_id)
        @task_id = task_id
      end

      def id
        @task_id
      end

      def state
        Task.state(@task_id)
      end

      def running?
        [:queued, :running, :ready].include?(state)
      end

      def complete?
        Task.terminal_state?(state)
      end

      def cancel
        Task.cancel(@task_id)
      end

      def outcome
        Task.outcome(@task_id)
      end

      def snapshot
        Task.snapshot(@task_id)
      end

      def ready?
        state == :ready
      end

      def cancel_requested?
        value = snapshot
        !!(value && value[:cancel_requested])
      end

      def progress
        snapshot = Task.snapshot(@task_id)
        snapshot && snapshot[:progress]
      end

      def stage
        snapshot = Task.snapshot(@task_id)
        snapshot ? snapshot[:stage].to_s : ""
      end
    end

    class WorkerContext
      def initialize(task_id)
        @task_id = task_id
      end

      def cancelled?
        Task.cancel_requested?(@task_id)
      end

      def checkpoint!
        raise Cancelled, "Task cancelled." if cancelled?
        true
      end

      def report(progress = nil, stage = nil)
        Task.report(@task_id, progress, stage)
      end

      def report_ratio(current, total, stage = nil)
        amount = total.to_f
        return indeterminate!(stage) if amount <= 0
        Task.report(@task_id, current.to_f / amount, stage)
      end

      def indeterminate!(stage = nil)
        Task.indeterminate(@task_id, stage)
      end

      def fail!(message, code = :failed)
        raise Failed.new(message, code)
      end
    end

    @main_thread = Thread.current if defined?(Thread)
    @mutex = defined?(Mutex) ? Mutex.new : nil
    @tasks = {}
    @queue = []
    @history = []
    @next_id = 0
    @updating = false
    @shutting_down = false

    class << self
      def start(key = nil, options = {}, &worker)
        raise ArgumentError, "A task worker block is required." unless worker
        raise "Background tasks are unavailable on this platform." unless supported?
        opts = normalize_options(options)
        task_key = normalize_key(key || opts[:key] || "task")
        duplicate = active_for_key(task_key)
        return Handle.new(duplicate[:id]) if duplicate && opts[:duplicate] == :reuse
        return reject_task(task_key, opts, :duplicate, "Task is already running.") if duplicate && opts[:duplicate] == :reject

        task = build_task(task_key, opts, worker)
        synchronize do
          @tasks[task[:id]] = task
          if duplicate && opts[:duplicate] == :queue
            task[:state] = :queued
            @queue << task[:id]
          else
            launch_task(task)
          end
        end
        Handle.new(task[:id])
      rescue Exception => e
        log_exception("Background task could not start", e)
        raise
      end

      def update
        return false unless main_thread?
        return false if @updating || @shutting_down
        @updating = true
        collect_finished_workers
        apply_timeouts
        deliver_running_progress
        deliver_ready_tasks if delivery_ready?
        launch_queued_tasks
        Reloaded::Toast.update if defined?(Reloaded::Toast) && Reloaded::Toast.respond_to?(:update)
        true
      rescue Exception => e
        log_exception("Background task update failed", e)
        false
      ensure
        @updating = false
      end

      def running?(key = nil)
        if key.nil?
          tasks.any? { |entry| [:queued, :running, :ready].include?(entry[:state]) }
        else
          !active_for_key(normalize_key(key)).nil?
        end
      rescue
        false
      end

      def active
        tasks.select { |entry| [:queued, :running, :ready].include?(entry[:state]) }.map { |entry| public_snapshot(entry) }
      end

      def recent
        synchronize { @history.dup }
      rescue
        []
      end

      def state(task_or_id)
        task = task_for(task_or_id)
        task ? task[:state] : nil
      end

      def snapshot(task_or_id)
        task = task_for(task_or_id)
        task ? public_snapshot(task) : nil
      end

      def outcome(task_or_id)
        task = task_for(task_or_id)
        task && task[:outcome]
      end

      def cancel(task_or_id)
        task = task_for(task_or_id)
        return false unless task
        synchronize do
          return false if terminal_state?(task[:state])
          task[:cancel_requested] = true
          if task[:state] == :queued
            @queue.delete(task[:id])
            mark_ready(task, :cancelled, nil, :cancelled, "Task cancelled.")
          end
        end
        true
      rescue
        false
      end

      def cancel_owner(owner)
        owner_id = normalize_key(owner)
        selected = tasks.select { |task| task[:owner] == owner_id && !terminal_state?(task[:state]) }
        selected.each { |task| cancel(task[:id]) }
        selected.length
      rescue
        0
      end

      def shutdown(wait = 0.5)
        @shutting_down = true
        tasks.each { |task| cancel(task[:id]) unless terminal_state?(task[:state]) }
        deadline = Time.now.to_f + [wait.to_f, 0.0].max
        tasks.each do |task|
          thread = task[:thread]
          next unless thread && thread.alive?
          remaining = deadline - Time.now.to_f
          break if remaining <= 0
          thread.join(remaining) rescue nil
        end
        collect_finished_workers
        true
      rescue Exception => e
        log_exception("Background task shutdown failed", e)
        false
      ensure
        @shutting_down = false
      end

      def supported?
        return true unless defined?(Reloaded::Platform)
        Reloaded::Platform.supports?(:background_tasks)
      rescue
        false
      end

      def main_thread?
        !defined?(Thread) || Thread.current == @main_thread
      rescue
        true
      end

      def updating?
        !!@updating
      rescue
        false
      end

      def assert_main_thread!
        raise "This operation must run on the game thread." unless main_thread?
        true
      end

      def terminal_state?(value)
        TERMINAL_STATES.include?(value.to_sym)
      rescue
        false
      end

      def cancel_requested?(task_id)
        task = task_for(task_id)
        !!(task && task[:cancel_requested])
      rescue
        false
      end

      def report(task_id, progress = nil, stage = nil)
        task = task_for(task_id)
        return false unless task
        synchronize do
          task[:progress] = normalize_progress(progress) unless progress.nil?
          task[:stage] = stage.to_s unless stage.nil?
          task[:progress_dirty] = true
        end
        true
      rescue
        false
      end

      def indeterminate(task_id, stage = nil)
        task = task_for(task_id)
        return false unless task
        synchronize do
          task[:progress] = nil
          task[:stage] = stage.to_s unless stage.nil?
          task[:progress_dirty] = true
        end
        true
      rescue
        false
      end

      private

      def normalize_options(options)
        source = options.is_a?(Hash) ? options.dup : {}
        duplicate = (source[:duplicate] || :reuse).to_sym rescue :reuse
        duplicate = :reuse unless DUPLICATE_POLICIES.include?(duplicate)
        {
          :owner => normalize_key(source[:owner] || :reloaded),
          :duplicate => duplicate,
          :timeout => [source[:timeout].to_f, 0.0].max,
          :on_success => source[:on_success],
          :on_failure => source[:on_failure],
          :on_cancel => source[:on_cancel],
          :on_complete => source[:on_complete],
          :on_progress => source[:on_progress],
          :notify => source[:notify],
          :history => source.key?(:history) ? !!source[:history] : true,
          :metadata => source[:metadata].is_a?(Hash) ? source[:metadata].dup : {}
        }
      end

      def build_task(key, options, worker)
        @next_id += 1
        {
          :id => @next_id,
          :key => key,
          :owner => options[:owner],
          :state => :queued,
          :worker => worker,
          :thread => nil,
          :started_at => nil,
          :finished_at => nil,
          :value => nil,
          :error => nil,
          :error_code => nil,
          :error_message => "",
          :progress => nil,
          :stage => "",
          :progress_dirty => false,
          :cancel_requested => false,
          :timed_out => false,
          :delivered => false,
          :outcome => nil,
          :options => options
        }
      end

      def launch_task(task)
        task[:state] = :running
        task[:started_at] = Time.now
        context = WorkerContext.new(task[:id])
        task[:thread] = Thread.new do
          begin
            context.checkpoint!
            task[:value] = task[:worker].call(context)
          rescue Cancelled => e
            task[:error] = e
            task[:error_code] = :cancelled
            task[:error_message] = e.message.to_s
          rescue Failed => e
            task[:error] = e
            task[:error_code] = e.code
            task[:error_message] = e.message.to_s
          rescue Exception => e
            task[:error] = e
            task[:error_code] = :exception
            task[:error_message] = e.message.to_s
          ensure
            task[:worker_finished] = true
          end
        end
        task[:thread].report_on_exception = false if task[:thread].respond_to?(:report_on_exception=)
      end

      def collect_finished_workers
        tasks.each do |task|
          next unless task[:state] == :running
          thread = task[:thread]
          next if thread && thread.alive?
          thread.join rescue nil if thread
          if task[:timed_out]
            mark_ready(task, :timed_out, nil, :timeout, "Task timed out.")
          elsif task[:cancel_requested] || task[:error].is_a?(Cancelled)
            mark_ready(task, :cancelled, nil, :cancelled, task[:error_message])
          elsif task[:error]
            mark_ready(task, :failed, nil, task[:error_code] || :exception, task[:error_message])
          else
            mark_ready(task, :succeeded, task[:value], nil, "")
          end
        end
      end

      def apply_timeouts
        now = Time.now.to_f
        tasks.each do |task|
          next unless task[:state] == :running
          timeout = task[:options][:timeout].to_f
          next if timeout <= 0 || !task[:started_at]
          if now - task[:started_at].to_f >= timeout
            task[:timed_out] = true
            task[:cancel_requested] = true
          end
        end
      end

      def mark_ready(task, final_state, value, error_code, error_message)
        task[:pending_state] = final_state
        task[:value] = value unless value.nil?
        task[:error_code] = error_code
        task[:error_message] = error_message.to_s
        task[:finished_at] = Time.now
        task[:state] = :ready
      end

      def deliver_ready_tasks
        tasks.each do |task|
          next unless task[:state] == :ready
          deliver_progress(task)
          final_state = task[:pending_state] || :failed
          outcome = build_outcome(task, final_state)
          task[:outcome] = outcome
          callback = case final_state
                     when :succeeded then task[:options][:on_success]
                     when :cancelled then task[:options][:on_cancel]
                     else task[:options][:on_failure]
                     end
          safe_callback(callback, outcome)
          safe_callback(task[:options][:on_complete], outcome)
          show_notification(task, outcome)
          task[:state] = final_state
          task[:delivered] = true
          record_history(task) if task[:options][:history]
          log_failure(task, outcome) if outcome.failed?
        end
      end

      def deliver_running_progress
        tasks.each do |task|
          next unless task[:state] == :running && task[:progress_dirty]
          deliver_progress(task)
        end
      end

      def deliver_progress(task)
        return unless task[:progress_dirty]
        callback = task[:options][:on_progress]
        task[:progress_dirty] = false
        safe_callback(callback, public_snapshot(task)) if callback
      end

      def build_outcome(task, state_value)
        started = task[:started_at]
        finished = task[:finished_at] || Time.now
        Outcome.new(
          :id => task[:id], :key => task[:key], :owner => task[:owner],
          :state => state_value, :value => task[:value],
          :error_code => task[:error_code], :error_message => task[:error_message],
          :started_at => started, :finished_at => finished,
          :duration => started ? finished.to_f - started.to_f : 0.0,
          :progress => task[:progress], :stage => task[:stage]
        )
      end

      def show_notification(task, outcome)
        config = task[:options][:notify]
        return if config.nil? || config == false || !defined?(Reloaded::Toast)
        options = config.is_a?(Hash) ? config.dup : {}
        text = if outcome.success?
                 options[:success] || options[:message]
               elsif outcome.cancelled?
                 options[:cancel]
               else
                 options[:failure] || outcome.error_message
               end
        return if text.to_s.empty?
        mode = (options[:mode] || :ok).to_sym rescue :ok
        theme = outcome.success? ? (options[:success_theme] || :success) : (options[:failure_theme] || :error)
        Reloaded::Toast.show(text.to_s, :mode => mode, :theme => theme)
      rescue Exception => e
        log_exception("Background task notification failed", e)
      end

      def launch_queued_tasks
        queued_ids = synchronize { @queue.dup }
        queued_ids.each do |task_id|
          task = task_for(task_id)
          next unless task && task[:state] == :queued
          next if active_for_key(task[:key], task[:id])
          synchronize do
            @queue.delete(task_id)
            launch_task(task)
          end
        end
      end

      def reject_task(key, options, code, message)
        task = build_task(key, options, nil)
        @tasks[task[:id]] = task
        mark_ready(task, :rejected, nil, code, message)
        Handle.new(task[:id])
      end

      def active_for_key(key, except_id = nil)
        tasks.find do |task|
          task[:id] != except_id && task[:key] == key && [:queued, :running, :ready].include?(task[:state])
        end
      end

      def task_for(task_or_id)
        id = task_or_id.respond_to?(:id) ? task_or_id.id : task_or_id
        synchronize { @tasks[id.to_i] }
      rescue
        nil
      end

      def tasks
        synchronize { @tasks.values.dup }
      rescue
        []
      end

      def public_snapshot(task)
        {
          :id => task[:id], :key => task[:key], :owner => task[:owner],
          :state => task[:state], :progress => task[:progress],
          :stage => task[:stage].to_s, :cancel_requested => !!task[:cancel_requested],
          :started_at => task[:started_at], :finished_at => task[:finished_at],
          :metadata => task[:options][:metadata].dup
        }
      end

      def record_history(task)
        @history << task[:outcome]
        @history.shift while @history.length > DEFAULT_HISTORY_LIMIT
      end

      def delivery_ready?
        return false if defined?(Reloaded::PopupWindow) && Reloaded::PopupWindow.respond_to?(:modal_active?) && Reloaded::PopupWindow.modal_active?
        input_neutral?
      rescue
        true
      end

      def input_neutral?
        return true unless defined?(Input)
        names = [:USE, :BACK, :ACTION, :SPECIAL, :UP, :DOWN, :LEFT, :RIGHT, :MOUSELEFT, :MOUSERIGHT]
        names.none? do |name|
          next false unless Input.const_defined?(name)
          Input.press?(Input.const_get(name)) rescue false
        end
      rescue
        true
      end

      def safe_callback(callback, value)
        callback.call(value) if callback.respond_to?(:call)
      rescue Exception => e
        log_exception("Background task callback failed", e)
      end

      def normalize_key(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, "_").sub(/\A_+/, "").sub(/_+\z/, "").to_sym
      rescue
        :task
      end

      def normalize_progress(value)
        number = value.to_f
        [[number, 0.0].max, 1.0].min
      rescue
        nil
      end

      def synchronize(&block)
        @mutex ? @mutex.synchronize(&block) : yield
      end

      def log_failure(task, outcome_value)
        return unless defined?(Reloaded::Log)
        message = "Task #{task[:key]} failed"
        message += " (#{outcome_value.error_code})" if outcome_value.error_code
        message += ": #{outcome_value.error_message}" unless outcome_value.error_message.empty?
        Reloaded::Log.warning_once(message, :framework, :key => "task_failure:#{task[:id]}")
      rescue
      end

      def log_exception(message, error)
        Reloaded::Log.exception(message, error, :channel => :framework) if defined?(Reloaded::Log)
      rescue
      end
    end

    if defined?(Graphics) && Graphics.respond_to?(:update)
      module GraphicsUpdate
        def update(*args)
          result = super
          Reloaded::Task.update if defined?(Reloaded::Task)
          result
        end
      end
      class << Graphics
        prepend GraphicsUpdate unless ancestors.include?(GraphicsUpdate)
      end
      if defined?(Reloaded::Patches)
        Reloaded::Patches.register(
          :task_graphics_update,
          :target => "Graphics.update",
          :type => :prepend,
          :file => __FILE__,
          :owner => :reloaded,
          :reason => "Poll background task completion on the game thread."
        )
      end
    end
  end
end
