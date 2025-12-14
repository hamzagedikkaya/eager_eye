# frozen_string_literal: true

require_relative "eager_eye/version"
require_relative "eager_eye/configuration"
require_relative "eager_eye/issue"
require_relative "eager_eye/detectors/base"
require_relative "eager_eye/detectors/loop_association"
require_relative "eager_eye/detectors/serializer_nesting"
require_relative "eager_eye/detectors/missing_counter_cache"
require_relative "eager_eye/analyzer"

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
