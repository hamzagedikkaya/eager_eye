# frozen_string_literal: true

module EagerEye
  module Reporters
    class Console < Base
      COLORS = {
        red: "\e[31m",
        yellow: "\e[33m",
        green: "\e[32m",
        cyan: "\e[36m",
        reset: "\e[0m",
        bold: "\e[1m"
      }.freeze

      def initialize(issues, colorize: true)
        super(issues)
        @colorize = colorize
      end

      def report
        return no_issues_message if issues.empty?

        output = []
        output << header
        output << ""

        issues_by_file.each do |file_path, file_issues|
          output << file_section(file_path, file_issues)
        end

        output << separator
        output << summary
        output.join("\n")
      end

      private

      def no_issues_message
        colorize("No issues detected!", :green)
      end

      def header
        "#{colorize("EagerEye Analysis Results", :bold)}\n#{"=" * 25}"
      end

      def separator
        "-" * 40
      end

      def file_section(file_path, file_issues)
        [colorize(file_path, :cyan), *file_issues.map { |i| format_issue(i) }, ""].join("\n")
      end

      def format_issue(issue)
        detector_label = format_detector(issue.detector)
        severity_color = severity_to_color(issue.severity)

        line = "  Line #{issue.line_number}: "
        line += colorize("[#{detector_label}]", severity_color)
        line += " #{issue.message}"

        line += "\n           #{colorize("Suggestion:", :green)} #{issue.suggestion}" if issue.suggestion

        line
      end

      def severity_to_color(severity)
        { error: :red, warning: :yellow, info: :cyan }.fetch(severity, :yellow)
      end

      def format_detector(detector)
        detector.to_s.split("_").map(&:capitalize).join
      end

      def summary
        "Total: #{pluralize(issues.size, "issue")} " \
          "(#{pluralize(error_count, "error")}, #{pluralize(warning_count, "warning")}, #{info_count} info)"
      end

      def pluralize(count, word)
        "#{count} #{word}#{"s" unless count == 1}"
      end

      def colorize(text, color)
        return text unless @colorize

        "#{COLORS[color]}#{text}#{COLORS[:reset]}"
      end
    end
  end
end
