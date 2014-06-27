require 'open-uri'
require 'rspec'
require 'rspec/core'
require 'rspec/core/formatters/documentation_formatter'
require 'rspec/core/formatters/json_formatter'
require 'pact/provider/pact_helper_locator'
require 'pact/provider/rspec/formatter'
require 'pact/provider/rspec/silent_json_formatter'
require 'pact/project_root'
require 'pact/rspec'

require_relative 'rspec'


module Pact
  module Provider
    class PactSpecRunner

      include Pact::Provider::RSpec::ClassMethods

      attr_reader :spec_definitions
      attr_reader :options
      attr_reader :output

      def initialize spec_definitions, options = {}
        @spec_definitions = spec_definitions
        @options = options
        @results = nil
      end

      def run
        begin
          configure_rspec
          initialize_specs
          run_specs
        ensure
          ::RSpec.reset
          Pact.clear_provider_world
        end
      end

      private

      def initialize_specs
        spec_definitions.each do | spec_definition |
          options = {
            consumer: spec_definition[:consumer],
            save_pactfile_to_tmp: true,
            criteria: @options[:criteria]
          }
          honour_pactfile spec_definition[:uri], options
        end
      end

      def configure_rspec
        config = ::RSpec.configuration

        config.color = true
        config.pattern = "pattern which doesn't match any files"
        config.backtrace_inclusion_patterns = [Regexp.new(Dir.getwd), /pact.*pact\.rake.*2/]
        config.backtrace_exclusion_patterns << /pact/

        config.extend Pact::Provider::RSpec::ClassMethods
        config.include Pact::Provider::RSpec::InstanceMethods
        config.include Pact::Provider::TestMethods

        if options[:silent]
          config.output_stream = StringIO.new
          config.error_stream = StringIO.new
        else
          config.error_stream = Pact.configuration.error_stream
          config.output_stream = Pact.configuration.output_stream
        end

        config.add_formatter Pact::Provider::RSpec::Formatter
        config.add_formatter Pact::Provider::RSpec::SilentJsonFormatter

        config.before(:suite) do
          # Preload app before suite so the classes loaded in memory are consistent for
          # before :each and after :each hooks.
          # Otherwise the app and all its dependencies are loaded between the first before :each
          # and the first after :each, leading to inconsistent behaviour
          # (eg. with database_cleaner transactions)
          Pact.configuration.provider.app
        end
      end

      def run_specs
        exit_code = if Pact::RSpec.runner_defined?
          ::RSpec::Core::Runner.run(rspec_runner_options,
            ::RSpec.configuration.output_stream, ::RSpec.configuration.error_stream)
        else
          ::RSpec::Core::CommandLine.new(NoConfigurationOptions.new)
            .run(::RSpec.configuration.output_stream, ::RSpec.configuration.error_stream)
        end
        @output = JSON.parse(Pact.provider_world.json_formatter_stream.string, symbolize_keys: true)
        exit_code
      end

      def rspec_runner_options
        ["--options", Pact.project_root.join("lib/pact/provider/rspec/custom_options_file").to_s]
      end

      def class_exists? name
        Kernel.const_get name
      rescue NameError
        false
      end

      class NoConfigurationOptions
        def method_missing(method, *args, &block)
          # Do nothing!
        end
      end

    end
  end
end
