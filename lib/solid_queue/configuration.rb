# frozen_string_literal: true

module SolidQueue
  class Configuration
    WORKER_DEFAULTS = {
      pool_size: 5,
      polling_interval: 0.1
    }

    SCHEDULER_DEFAULTS = {
      batch_size: 500,
      polling_interval: 300
    }

    def initialize(mode: :work, load_from: nil)
      @mode = mode
      @raw_config = config_from(load_from)
    end

    def runners
      case mode
      when :schedule then scheduler
      when :work     then workers
      when :all      then [ scheduler ] + workers
      else           raise "Invalid mode #{mode}"
      end
    end

    def workers
      if mode.in? %i[ work all]
        workers_options.values.map { |worker_options| SolidQueue::Worker.new(**worker_options) }
      else
        []
      end
    end

    def scheduler
      if mode.in? %i[ schedule all]
        SolidQueue::Scheduler.new(**scheduler_options)
      end
    end

    def max_number_of_threads
      # At most pool_size thread in each worker + 1 thread for the worker + 1 thread for the heartbeat task
      workers_options.values.map { |options| options[:pool_size] }.max + 2
    end

    private
      attr_reader :raw_config, :mode

      def config_from(file_or_hash, env: Rails.env)
        config = load_config_from(file_or_hash)
        config[env.to_sym] ? config[env.to_sym] : config
      end

      def workers_options
        @workers_options ||= (raw_config[:workers] || {}).each_with_object({}) do |(queue_string, options), hsh|
          hsh[queue_string] = options.merge(queues: queue_string.to_s).with_defaults(WORKER_DEFAULTS)
        end.deep_symbolize_keys
      end

      def scheduler_options
        (raw_config[:scheduler] || {}).with_defaults(SCHEDULER_DEFAULTS)
      end

      def load_config_from(file_or_hash)
        case file_or_hash
        when Pathname then load_config_file file_or_hash
        when String   then load_config_file Pathname.new(file_or_hash)
        when NilClass then load_config_file default_config_file
        when Hash     then file_or_hash.dup
        else          raise "Solid Queue cannot be initialized with #{file_or_hash.inspect}"
        end
      end

      def load_config_file(file)
        if file.exist?
          ActiveSupport::ConfigurationFile.parse(file).deep_symbolize_keys
        else
          raise "Configuration file not found in #{file}"
        end
      end

      def default_config_file
        Rails.root.join("config/solid_queue.yml").tap do |config_file|
          raise "Configuration for Solid Queue not found in #{config_file}" unless config_file.exist?
        end
      end
  end
end
