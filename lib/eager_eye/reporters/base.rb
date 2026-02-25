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

      def severity_counts
        @severity_counts ||= issues.map(&:severity).tally
      end

      def info_count = severity_counts.fetch(:info, 0)
      def warning_count = severity_counts.fetch(:warning, 0)
      def error_count = severity_counts.fetch(:error, 0)
    end
  end
end
