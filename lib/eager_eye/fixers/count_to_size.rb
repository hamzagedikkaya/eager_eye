# frozen_string_literal: true

module EagerEye
  module Fixers
    class CountToSize < Base
      def fixable?
        issue.detector == :count_in_iteration &&
          line_content&.include?(".count")
      end

      protected

      def fixed_content
        line_content.gsub(/\.count\b/, ".size")
      end
    end
  end
end
