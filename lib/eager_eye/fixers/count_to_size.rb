# frozen_string_literal: true

module EagerEye
  module Fixers
    class CountToSize < Base
      def fixable?
        issue.detector == :count_in_iteration &&
          single_line_count?
      end

      protected

      def fixed_content
        line_content.sub(/\.count\b/, ".size")
      end

      private

      def single_line_count?
        line_content&.match?(/\.count\b/)
      end
    end
  end
end
