# frozen_string_literal: true

module EagerEye
  class CommentParser
    FILE_DISABLE_PATTERN = /eager_eye:disable-file\s+(.+?)(?:\s+--|$)/i
    NEXT_LINE_PATTERN = /eager_eye:disable-next-line(?:\s+(.+?))?(?:\s+--|$)/i
    BLOCK_START_PATTERN = /eager_eye:disable-block(?:\s+(.+?))?(?:\s+--|$)/i
    BLOCK_END_PATTERN = /eager_eye:enable-block(?:\s+(.+?))?(?:\s+--|$)/i
    INLINE_DISABLE_PATTERN = /eager_eye:disable\s+(.+?)(?:\s+--|$)/i
    ENABLE_PATTERN = /eager_eye:enable(?:\s+(.+?))?(?:\s+--|$)/i

    def initialize(source_code)
      @source_code = source_code.encode("UTF-8", invalid: :replace, undef: :replace)
      @lines = @source_code.lines
      @disabled_ranges = Hash.new { |h, k| h[k] = [] }
      @file_disabled = Set.new
      @current_disabled = Set.new
      parse_comments
    end

    def disabled_at?(line_number, detector_name)
      return true if @file_disabled.include?(detector_name.to_s)
      return true if @file_disabled.include?("all")

      detector = detector_name.to_s
      @disabled_ranges[detector].any? { |range| range.cover?(line_number) } ||
        @disabled_ranges["all"].any? { |range| range.cover?(line_number) }
    end

    private

    def parse_comments
      @lines.each_with_index do |line, index|
        line_num = index + 1
        process_line(line, line_num)
      end

      close_unclosed_blocks
    end

    def process_line(line, line_num)
      directive = detect_directive(line, line_num)
      apply_directive(directive, line_num) if directive
    end

    def detect_directive(line, line_num)
      detect_file_directive(line, line_num) ||
        detect_next_line_directive(line) ||
        detect_block_end_directive(line) ||
        detect_block_or_inline_directive(line)
    end

    def detect_file_directive(line, line_num)
      return unless line_num <= 5 && line =~ FILE_DISABLE_PATTERN

      detectors = parse_detector_names(::Regexp.last_match(1) || "all")
      { type: :file, detectors: detectors }
    end

    def detect_next_line_directive(line)
      return unless line =~ NEXT_LINE_PATTERN

      detectors = parse_detector_names(::Regexp.last_match(1) || "all")
      { type: :next_line, detectors: detectors }
    end

    def detect_block_end_directive(line)
      return unless line =~ ENABLE_PATTERN

      detectors = parse_detector_names(::Regexp.last_match(1) || "all")
      { type: :block_end, detectors: detectors }
    end

    def detect_block_or_inline_directive(line)
      if line =~ BLOCK_START_PATTERN && !code_before_comment?(line)
        detectors = parse_detector_names(::Regexp.last_match(1) || "all")
        return { type: :block_start, detectors: detectors }
      end

      return unless line =~ INLINE_DISABLE_PATTERN

      detectors = parse_detector_names(::Regexp.last_match(1) || "all")

      if code_before_comment?(line)
        { type: :inline, detectors: detectors }
      else
        { type: :block_start, detectors: detectors }
      end
    end

    def apply_directive(directive, line_num)
      case directive[:type]
      when :file then apply_file_disable(directive[:detectors])
      when :next_line then apply_next_line_disable(directive[:detectors], line_num)
      when :block_start then apply_block_start(directive[:detectors], line_num)
      when :block_end then apply_block_end(directive[:detectors], line_num)
      when :inline then apply_inline_disable(directive[:detectors], line_num)
      end
    end

    def apply_file_disable(detectors)
      @file_disabled.merge(detectors)
    end

    def apply_next_line_disable(detectors, line_num)
      next_line = line_num + 1
      detectors.each { |d| @disabled_ranges[d] << (next_line..next_line) }
    end

    def apply_block_start(detectors, line_num)
      detectors.each { |d| @current_disabled << { detector: d, start: line_num } }
    end

    def apply_block_end(detectors, line_num)
      detectors.each do |d|
        entry = @current_disabled.find { |e| e[:detector] == d }
        next unless entry

        @disabled_ranges[d] << (entry[:start]..line_num)
        @current_disabled.delete(entry)
      end
    end

    def apply_inline_disable(detectors, line_num)
      detectors.each { |d| @disabled_ranges[d] << (line_num..line_num) }
    end

    def close_unclosed_blocks
      @current_disabled.each do |entry|
        @disabled_ranges[entry[:detector]] << (entry[:start]..@lines.size)
      end
    end

    def inline_disable?(line)
      code_part = line.split("#").first
      code_part && !code_part.strip.empty?
    end

    def code_before_comment?(line)
      code_part = line.split("#").first
      code_part && !code_part.strip.empty?
    end

    def parse_detector_names(str)
      return ["all"] if str.nil? || str.strip.empty?

      str.split(/[,\s]+/).map(&:strip).reject(&:empty?).map do |name|
        normalize_detector_name(name)
      end
    end

    def normalize_detector_name(name)
      name.gsub(/([A-Z])/) { "_#{::Regexp.last_match(1).downcase}" }
          .sub(/^_/, "")
          .downcase
    end
  end
end
