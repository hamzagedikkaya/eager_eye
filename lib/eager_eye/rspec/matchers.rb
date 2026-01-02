# frozen_string_literal: true

module EagerEye
  module RSpec
    module Matchers
      def pass_eager_eye(options = {})
        PassEagerEyeMatcher.new(options)
      end

      class PassEagerEyeMatcher
        def initialize(options = {})
          @only = options[:only]
          @exclude = options[:exclude] || []
          @max_issues = options[:max_issues] || 0
          @issues = []
          @path = nil
        end

        def matches?(path)
          @path = path
          configure_eager_eye
          @issues = EagerEye::Analyzer.new(paths: [@path]).run
          @issues.count <= @max_issues
        end

        def failure_message
          message = "expected #{@path} to pass EagerEye analysis"
          message += " (max #{@max_issues} issues)" if @max_issues.positive?
          message += ", but found #{@issues.count} issue(s):\n\n"

          @issues.group_by(&:file_path).each do |file, file_issues|
            message += "#{file}:\n"
            file_issues.each do |issue|
              message += "  Line #{issue.line_number}: [#{issue.detector}] #{issue.message}\n"
            end
            message += "\n"
          end

          message
        end

        def failure_message_when_negated
          "expected #{@path} to have EagerEye issues, but it passed"
        end

        def description
          desc = "pass EagerEye analysis"
          desc += " for #{@only.join(", ")}" if @only
          desc += " (max #{@max_issues} issues)" if @max_issues.positive?
          desc
        end

        private

        def configure_eager_eye
          EagerEye.reset_configuration!
          EagerEye.configure do |config|
            config.enabled_detectors = @only if @only
            config.excluded_paths = @exclude unless @exclude.empty?
            config.fail_on_issues = false
          end
        end
      end
    end
  end
end
