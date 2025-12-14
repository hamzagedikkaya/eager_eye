# frozen_string_literal: true

require "rails/railtie"

module EagerEye
  class Railtie < Rails::Railtie
    railtie_name :eager_eye

    rake_tasks do
      namespace :eager_eye do
        desc "Analyze Rails application for N+1 query issues"
        task analyze: :environment do
          require "eager_eye"

          load_config_file

          analyzer = EagerEye::Analyzer.new
          issues = analyzer.run

          reporter = EagerEye::Reporters::Console.new(issues)
          puts reporter.report

          exit 1 if issues.any? && EagerEye.configuration.fail_on_issues
        end

        desc "Analyze and output results as JSON"
        task json: :environment do
          require "eager_eye"

          load_config_file

          analyzer = EagerEye::Analyzer.new
          issues = analyzer.run

          reporter = EagerEye::Reporters::Json.new(issues, pretty: true)
          puts reporter.report

          exit 1 if issues.any? && EagerEye.configuration.fail_on_issues
        end

        def load_config_file
          config_file = Rails.root.join(".eager_eye.yml")
          return unless File.exist?(config_file)

          require "yaml"
          config = YAML.load_file(config_file, symbolize_names: true)

          EagerEye.configure do |c|
            c.excluded_paths = config[:excluded_paths] if config[:excluded_paths]
            c.enabled_detectors = config[:enabled_detectors].map(&:to_sym) if config[:enabled_detectors]
            c.app_path = config[:app_path] if config[:app_path]
            c.fail_on_issues = config[:fail_on_issues] if config.key?(:fail_on_issues)
          end
        end
      end
    end

    # Generate initializer for configuration
    generators do
      require_relative "generators/install_generator"
    end
  end
end
