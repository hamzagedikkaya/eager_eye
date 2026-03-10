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
      pluck_to_array: Detectors::PluckToArray,
      delegation_n_plus_one: Detectors::DelegationNPlusOne,
      decorator_n_plus_one: Detectors::DecoratorNPlusOne,
      scope_chain_n_plus_one: Detectors::ScopeChainNPlusOne
    }.freeze

    attr_reader :paths, :issues, :association_preloads, :delegation_maps, :scope_maps

    def initialize(paths: nil)
      @paths = Array(paths || EagerEye.configuration.app_path)
      @issues = []
      @association_preloads = {}
      @delegation_maps = {}
      @scope_maps = {}
    end

    def run
      @issues = []
      collect_model_metadata
      ruby_files.each { |file_path| analyze_file(file_path) }
      @issues
    end

    private

    def collect_model_metadata
      model_files.each do |file_path|
        ast = parse_source(File.read(file_path))
        next unless ast

        model_name = extract_model_name(file_path)

        assoc_parser = AssociationParser.new
        assoc_parser.parse_model(ast, model_name)
        @association_preloads.merge!(assoc_parser.preloaded_associations)

        deleg_parser = DelegationParser.new
        deleg_parser.parse_model(ast, model_name)
        @delegation_maps.merge!(deleg_parser.delegation_maps)

        scope_parser = ScopeParser.new
        scope_parser.parse_model(ast, model_name)
        @scope_maps.merge!(scope_parser.scope_maps)
      rescue Errno::ENOENT, Errno::EACCES
        next
      end
    end

    def model_files
      Dir.glob(File.join(@paths[0], "models", "**", "*.rb"))
    end

    def extract_model_name(file_path)
      name = File.basename(file_path, ".rb")
      name.respond_to?(:camelize) ? name.camelize : name.split("_").map(&:capitalize).join
    end

    def ruby_files
      paths.flat_map { |path| resolve_path(path) }.reject { |file| excluded?(file) }
    end

    def resolve_path(path)
      return [path] if File.file?(path)
      return Dir.glob(File.join(path, "**", "*.rb")) if File.directory?(path)

      Dir.glob(path)
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
        file_issues = detector.detect(*detector_args(detector, ast, file_path))
        @issues.concat(file_issues.select do |issue|
          !comment_parser.disabled_at?(issue.line_number, issue.detector) &&
            issue.meets_minimum_severity?(min_severity)
        end)
      end
    rescue Errno::ENOENT, Errno::EACCES => e
      warn "EagerEye: Could not read file #{file_path}: #{e.message}"
    end

    def parse_source(source)
      Parser::CurrentRuby.parse(source)
    rescue Parser::SyntaxError
      nil
    end

    def detector_args(detector, ast, file_path)
      args = [ast, file_path]
      args << @association_preloads if detector.is_a?(Detectors::LoopAssociation)
      args << @delegation_maps if detector.is_a?(Detectors::DelegationNPlusOne)
      args << @scope_maps if detector.is_a?(Detectors::ScopeChainNPlusOne)
      args
    end

    def enabled_detectors
      @enabled_detectors ||= EagerEye.configuration.enabled_detectors.filter_map do |name|
        DETECTOR_CLASSES[name]&.new
      end
    end
  end
end
