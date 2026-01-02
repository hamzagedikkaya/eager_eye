# frozen_string_literal: true

module EagerEye
  class Issue
    attr_reader :detector, :file_path, :line_number, :message, :severity, :suggestion

    VALID_SEVERITIES = %i[info warning error].freeze
    SEVERITY_ORDER = { info: 0, warning: 1, error: 2 }.freeze

    def initialize(detector:, file_path:, line_number:, message:, severity: :warning, suggestion: nil)
      @detector = detector
      @file_path = file_path
      @line_number = line_number
      @message = message
      @severity = validate_severity(severity)
      @suggestion = suggestion
    end

    def severity_level
      SEVERITY_ORDER[severity]
    end

    def meets_minimum_severity?(min_severity)
      severity_level >= SEVERITY_ORDER.fetch(min_severity, 0)
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
      other.is_a?(Issue) && to_h == other.to_h
    end

    alias eql? ==

    def hash
      to_h.hash
    end

    private

    def validate_severity(severity)
      return severity if VALID_SEVERITIES.include?(severity)

      raise ArgumentError, "Invalid severity: #{severity}. Must be one of: #{VALID_SEVERITIES.join(", ")}"
    end
  end
end
