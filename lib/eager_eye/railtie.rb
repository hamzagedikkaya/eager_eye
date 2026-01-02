# frozen_string_literal: true

require "rails/railtie"

module EagerEye
  class Railtie < Rails::Railtie
    railtie_name :eager_eye

    rake_tasks do
      namespace :eager_eye do
        desc "Analyze Rails application for N+1 query issues"
        task analyze: :environment do
          puts run_analysis(EagerEye::Reporters::Console)
        end

        desc "Analyze and output results as JSON"
        task json: :environment do
          puts run_analysis(EagerEye::Reporters::Json, pretty: true)
        end

        def run_analysis(reporter_class, **opts)
          require "eager_eye"
          load_config_file
          issues = EagerEye::Analyzer.new.run
          exit 1 if issues.any? && EagerEye.configuration.fail_on_issues
          reporter_class.new(issues, **opts).report
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

    generators do
      require_relative "generators/install_generator"
    end
  end
end
