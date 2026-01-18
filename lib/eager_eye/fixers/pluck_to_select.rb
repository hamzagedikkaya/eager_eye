# frozen_string_literal: true

module EagerEye
  module Fixers
    class PluckToSelect < Base
      def fixable?
        issue.detector == :pluck_to_array &&
          issue.severity != :info &&
          single_line_pattern?
      end

      protected

      def fixed_content
        line_content.sub(/(\.where\s*\([^)]*)(\.pluck)(\((?::\w+)\))/) do
          "#{::Regexp.last_match(1)}.select#{::Regexp.last_match(3)}"
        end
      end

      private

      def single_line_pattern?
        line_content&.match?(/\.where\s*\([^)]*\.pluck\(/)
      end
    end
  end
end
