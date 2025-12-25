# frozen_string_literal: true

module EagerEye
  class Configuration
    attr_accessor :excluded_paths, :enabled_detectors, :app_path, :fail_on_issues,
                  :severity_levels, :min_severity

    DEFAULT_DETECTORS = %i[
      loop_association serializer_nesting missing_counter_cache
      custom_method_query count_in_iteration callback_query
      pluck_to_array
    ].freeze

    DEFAULT_SEVERITY_LEVELS = {
      loop_association: :error,
      serializer_nesting: :warning,
      missing_counter_cache: :info,
      custom_method_query: :warning,
      count_in_iteration: :warning,
      callback_query: :warning,
      pluck_to_array: :warning
    }.freeze

    VALID_SEVERITIES = %i[info warning error].freeze

    def initialize
      @excluded_paths = []
      @enabled_detectors = DEFAULT_DETECTORS.dup
      @app_path = "app"
      @fail_on_issues = true
      @severity_levels = DEFAULT_SEVERITY_LEVELS.dup
      @min_severity = :info
    end

    def severity_for(detector_name)
      severity_levels.fetch(detector_name.to_sym, :warning)
    end

    def valid_severity?(severity)
      VALID_SEVERITIES.include?(severity.to_sym)
    end
  end
end
