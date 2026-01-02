# frozen_string_literal: true

require "parser/current"

module EagerEye
  class Analyzer
    DETECTOR_CLASSES = {
      loop_association: Detectors::LoopAssociation,
      serializer_nesting: Detectors::SerializerNesting,
      missing_counter_cache: Detectors::MissingCounterCache,
      custom_method_query: Detectors::CustomMethodQuery,
      count_in_iteration: Detectors::CountInIteration,
      callback_query: Detectors::CallbackQuery,
      pluck_to_array: Detectors::PluckToArray
    }.freeze

    attr_reader :paths, :issues, :association_preloads

    def initialize(paths: nil)
      @paths = Array(paths || EagerEye.configuration.app_path)
      @issues = []
      @association_preloads = {}
    end

    def run
      @issues = []
      collect_association_preloads
      analyze_files
      @issues
    end

    private

    def collect_association_preloads
      model_files.each do |file_path|
        ast = parse_source(File.read(file_path))
        next unless ast

        parser = AssociationParser.new
        parser.parse_model(ast, extract_model_name(file_path))
        @association_preloads.merge!(parser.preloaded_associations)
      end
    rescue StandardError
      nil
    end

    def model_files
      Dir.glob(File.join(@paths[0], "models", "**", "*.rb"))
    end

    def extract_model_name(file_path)
      File.basename(file_path, ".rb").camelize
    end

    def analyze_files
      ruby_files.each { |file_path| analyze_file(file_path) }
    end

    def ruby_files
      all_files = paths.flat_map do |path|
        if File.file?(path)
          [path]
        elsif File.directory?(path)
          Dir.glob(File.join(path, "**", "*.rb"))
        else
          Dir.glob(path)
        end
      end

      all_files.reject { |file| excluded?(file) }
    end

    def excluded?(file_path)
      EagerEye.configuration.excluded_paths.any? do |pattern|
        File.fnmatch?(pattern, file_path, File::FNM_PATHNAME)
      end
    end

    def analyze_file(file_path)
      source = File.read(file_path)
      ast = parse_source(source)
      return unless ast

      comment_parser = CommentParser.new(source)
      min_severity = EagerEye.configuration.min_severity

      enabled_detectors.each do |detector|
        args = [ast, file_path]
        args << @association_preloads if detector.is_a?(Detectors::LoopAssociation)

        file_issues = detector.detect(*args)
        file_issues.reject! { |issue| comment_parser.disabled_at?(issue.line_number, issue.detector) }
        file_issues.select! { |issue| issue.meets_minimum_severity?(min_severity) }
        @issues.concat(file_issues)
      end
    rescue Errno::ENOENT, Errno::EACCES => e
      warn "EagerEye: Could not read file #{file_path}: #{e.message}"
    end

    def parse_source(source)
      Parser::CurrentRuby.parse(source)
    rescue Parser::SyntaxError
      nil
    end

    def enabled_detectors
      @enabled_detectors ||= EagerEye.configuration.enabled_detectors.filter_map do |name|
        detector_class = DETECTOR_CLASSES[name]
        detector_class&.new
      end
    end
  end
end
