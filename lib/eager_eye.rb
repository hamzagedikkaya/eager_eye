# frozen_string_literal: true

require_relative "eager_eye/version"
require_relative "eager_eye/configuration"
require_relative "eager_eye/issue"
require_relative "eager_eye/detectors/base"
require_relative "eager_eye/detectors/loop_association"
require_relative "eager_eye/detectors/serializer_nesting"
require_relative "eager_eye/detectors/missing_counter_cache"
require_relative "eager_eye/detectors/custom_method_query"
require_relative "eager_eye/detectors/count_in_iteration"
require_relative "eager_eye/detectors/callback_query"
require_relative "eager_eye/detectors/pluck_to_array"
require_relative "eager_eye/analyzer"
require_relative "eager_eye/reporters/base"
require_relative "eager_eye/reporters/console"
require_relative "eager_eye/reporters/json"
require_relative "eager_eye/cli"

module EagerEye
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

# Load Railtie only if Rails is defined
require_relative "eager_eye/railtie" if defined?(Rails::Railtie)
