# frozen_string_literal: true

require "rails/generators"

module EagerEye
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc "Creates an EagerEye configuration file"

      def create_config_file
        create_file ".eager_eye.yml", config_content
      end

      private

      def config_content
        <<~YAML
          # EagerEye Configuration
          # See https://github.com/hamzagedikkaya/eager_eye for documentation

          # Paths to exclude from analysis (glob patterns)
          excluded_paths:
            # - app/serializers/legacy/**
            # - lib/tasks/**

          # Detectors to enable (default: all)
          enabled_detectors:
            - loop_association
            - serializer_nesting
            - missing_counter_cache

          # Base path to analyze (default: app)
          app_path: app

          # Exit with error code when issues found (default: true)
          fail_on_issues: true
        YAML
      end
    end
  end
end
