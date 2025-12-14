# frozen_string_literal: true

module EagerEye
  class Issue
    attr_reader :detector, :file_path, :line_number, :message, :severity, :suggestion

    VALID_SEVERITIES = %i[warning error].freeze

    def initialize(detector:, file_path:, line_number:, message:, severity: :warning, suggestion: nil)
      @detector = detector
      @file_path = file_path
      @line_number = line_number
      @message = message
      @severity = validate_severity(severity)
      @suggestion = suggestion
    end

    def to_h
      {
        detector: detector,
        file_path: file_path,
        line_number: line_number,
        message: message,
        severity: severity,
        suggestion: suggestion
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    def ==(other)
      return false unless other.is_a?(Issue)

      detector == other.detector &&
        file_path == other.file_path &&
        line_number == other.line_number &&
        message == other.message &&
        severity == other.severity &&
        suggestion == other.suggestion
    end

    alias eql? ==

    def hash
      [detector, file_path, line_number, message, severity, suggestion].hash
    end

    private

    def validate_severity(severity)
      return severity if VALID_SEVERITIES.include?(severity)

      raise ArgumentError, "Invalid severity: #{severity}. Must be one of: #{VALID_SEVERITIES.join(", ")}"
    end
  end
end
