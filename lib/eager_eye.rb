# frozen_string_literal: true

require_relative "eager_eye/version"
require_relative "eager_eye/configuration"
require_relative "eager_eye/issue"
require_relative "eager_eye/detectors/base"
require_relative "eager_eye/detectors/loop_association"

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
