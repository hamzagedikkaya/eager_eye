# frozen_string_literal: true

module EagerEye
  class Configuration
    attr_accessor :excluded_paths, :enabled_detectors, :app_path, :fail_on_issues

    DEFAULT_DETECTORS = %i[
      loop_association serializer_nesting missing_counter_cache
      custom_method_query count_in_iteration callback_query
      pluck_to_array
    ].freeze

    def initialize
      @excluded_paths = []
      @enabled_detectors = DEFAULT_DETECTORS.dup
      @app_path = "app"
      @fail_on_issues = true
    end
  end
end
