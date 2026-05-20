# frozen_string_literal: true

require "json"
require "set"

module EagerEye
  # Loads a previous JSON report and filters out issues already present
  # in it. Used by `--baseline FILE` to surface only NEW issues introduced
  # since the baseline was captured — the typical brownfield-CI workflow:
  # accept existing issues, fail only on regressions.
  class Baseline
    class InvalidBaselineError < StandardError; end

    def self.load_issues(path)
      raw = File.read(path)
      data = JSON.parse(raw)
      issues_data = extract_issues_array(data)
      issues_data.map { |h| Issue.from_h(h) }
    rescue Errno::ENOENT
      raise InvalidBaselineError, "Baseline file not found: #{path}"
    rescue JSON::ParserError => e
      raise InvalidBaselineError, "Invalid JSON in baseline #{path}: #{e.message}"
    rescue KeyError => e
      raise InvalidBaselineError, "Baseline issue missing field #{e.message}"
    end

    def self.filter(current_issues, baseline_path)
      baseline_set = Set.new(load_issues(baseline_path))
      current_issues.reject { |issue| baseline_set.include?(issue) }
    end

    def self.extract_issues_array(data)
      case data
      when Array then data
      when Hash
        issues = data["issues"] || data[:issues]
        raise InvalidBaselineError, "Baseline JSON missing 'issues' array" unless issues.is_a?(Array)

        issues
      else
        raise InvalidBaselineError, "Baseline JSON must be an object with 'issues' or a plain array"
      end
    end
    private_class_method :extract_issues_array
  end
end
