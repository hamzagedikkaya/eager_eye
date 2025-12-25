# frozen_string_literal: true

module EagerEye
  module Reporters
    class Base
      attr_reader :issues

      def initialize(issues)
        @issues = issues
      end

      def report
        raise NotImplementedError, "Subclasses must implement #report"
      end

      protected

      def issues_by_file
        issues.group_by(&:file_path)
      end

      def info_count
        issues.count { |i| i.severity == :info }
      end

      def warning_count
        issues.count { |i| i.severity == :warning }
      end

      def error_count
        issues.count { |i| i.severity == :error }
      end
    end
  end
end
