# frozen_string_literal: true

require "parser/current"

module EagerEye
  # Serializers are the worst false-positive source because the detector sees the
  # serializer class in isolation: it cannot tell whether an association it flags
  # is actually eager-loaded by the controller that renders it, nor whether the
  # serializer is only ever handed a single record (no collection => no N+1).
  #
  # This parser scans the whole app for render sites — `XxxBlueprint.render*(arg,
  # view: :v)`, AMS `render json: arg, (each_)serializer: XxxSerializer` — and,
  # per (serializer, view), records:
  #   * preloaded_per_site : the associations eager-loaded on `arg` at each site
  #   * any_collection      : was `arg` ever a collection (vs a single record)?
  # An association preloaded at EVERY site, or a serializer only ever fed single
  # records, cannot cause an N+1 — letting the detector stay silent there.
  class SerializerUsageParser
    PRELOAD_METHODS = %i[includes preload eager_load].freeze
    RELATION_WRAPPERS = %i[pagy paginate page kaminari with_pagy].freeze
    SINGLE_RECORD_METHODS = %i[find find_by find_by! first first! last last! take take! sole find_sole_by
                               new build current_user current_account].freeze
    RENDER_METHODS = %i[render render_as_hash render_as_json render_as_json! serialize].freeze
    SERIALIZER_SUFFIXES = %w[Blueprint Serializer Resource].freeze

    # serializer_basename => [ { view: sym_or_nil, preloaded: Set, collection: bool }, ... ]
    attr_reader :usages

    def initialize
      @usages = Hash.new { |h, k| h[k] = [] }
    end

    def parse_file(ast)
      return unless ast

      each_scope(ast) do |body|
        var_values = collect_assignments(body)
        find_render_sites(body, var_values)
      end
    end

    # Whether an association read in `view` of `serializer` can be proven safe.
    # `view` is the Blueprinter view the field lives in (nil = a base/default
    # field, rendered by every site). The field is safe when, at every render
    # site that renders it, the association is eager-loaded OR the site passes a
    # single record. To avoid hiding a genuine N+1 we never conclude "safe" when
    # we cannot see the render sites for a named view (it may be rendered
    # dynamically) — only an EXISTING, uniformly-safe set of sites suppresses.
    def safe_access?(serializer, view, association)
      sites = sites_rendering(serializer, view)
      return false if sites.empty?

      sites.all? { |s| !s[:collection] || s[:preloaded].include?(association) }
    end

    def known_serializer?(serializer)
      @usages.key?(serializer)
    end

    private

    # Sites that render a field of the given view. A base field (view nil) is
    # rendered by every site. A named-view field is rendered by sites that
    # explicitly request that view.
    def sites_rendering(serializer, view)
      sites = @usages[serializer]
      return [] unless sites

      view.nil? ? sites : sites.select { |s| s[:view] == view }
    end

    def each_scope(ast)
      yield ast
      collect_defs(ast).each { |d| yield(def_body(d)) }
    end

    def collect_defs(node, acc = [])
      return acc unless node.is_a?(Parser::AST::Node)

      node.children.each do |child|
        next unless child.is_a?(Parser::AST::Node)

        acc << child if %i[def defs].include?(child.type)
        collect_defs(child, acc)
      end
      acc
    end

    def def_body(node)
      node.type == :def ? node.children[2] : node.children[3]
    end

    def collect_assignments(body)
      values = {}
      walk(body) do |node|
        case node.type
        when :lvasgn, :ivasgn
          values[node.children[0]] = node.children[1] if node.children[1]
        when :masgn
          collect_multi_assignment(node, values)
        end
      end
      values
    end

    def collect_multi_assignment(node, values)
      mlhs, rhs = node.children
      return unless mlhs && rhs

      mlhs.children.each do |t|
        next unless %i[lvasgn ivasgn].include?(t&.type)

        values[t.children[0]] = rhs
      end
    end

    def find_render_sites(body, var_values)
      walk(body) do |node|
        next unless node.type == :send && RENDER_METHODS.include?(node.children[1])

        serializer = serializer_name(node.children[0])
        next unless serializer

        arg = node.children[2]
        view = view_option(node)
        record_site(serializer, view, arg, var_values)
      end
    end

    # `Foo::BarBlueprint.render_as_hash` => "BarBlueprint"; for Alba, the receiver
    # is `BarResource.new(arg)` so peel the `.new`.
    def serializer_name(recv)
      return nil unless recv.is_a?(Parser::AST::Node)

      const = recv.type == :send ? recv.children[0] : recv
      return nil unless const.is_a?(Parser::AST::Node) && const.type == :const

      name = const.children[1].to_s
      SERIALIZER_SUFFIXES.any? { |s| name.end_with?(s) } ? name : nil
    end

    def view_option(node) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      node.children[3..].each do |arg|
        next unless arg.is_a?(Parser::AST::Node) && arg.type == :hash

        arg.children.each do |pair|
          k = pair.children[0]
          if k&.type == :sym && k.children[0] == :view && pair.children[1]&.type == :sym
            return pair.children[1].children[0]
          end
        end
      end
      nil
    end

    def record_site(serializer, view, arg, var_values)
      resolved = resolve_value(arg, var_values)
      @usages[serializer] << {
        view: view,
        preloaded: extract_preloads(resolved, var_values),
        collection: !single_record?(resolved, var_values)
      }
    end

    # Resolve a local/ivar render arg to the expression it was assigned, so
    # `render(user_points)` after `user_points = UserPoint.includes(:point)` is
    # seen as the relation, not an opaque variable.
    def resolve_value(node, var_values, depth = 0)
      return node if depth > 5 || !node.is_a?(Parser::AST::Node)
      return node unless %i[lvar ivar].include?(node.type)

      assigned = var_values[node.children[0]]
      assigned ? resolve_value(assigned, var_values, depth + 1) : node
    end

    def extract_preloads(node, var_values, depth = 0) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      preloads = Set.new
      return preloads if depth > 8 || !node.is_a?(Parser::AST::Node)

      current = node
      while current.is_a?(Parser::AST::Node) && current.type == :send
        current.children[2..].each { |a| collect_symbols(a, preloads) } if PRELOAD_METHODS.include?(current.children[1])
        current.children[2..].each do |a|
          if RELATION_WRAPPERS.include?(current.children[1])
            preloads.merge(extract_preloads(resolve_value(a, var_values), var_values,
                                            depth + 1))
          end
        end
        current = current.children[0]
      end
      preloads
    end

    def collect_symbols(arg, set) # rubocop:disable Metrics/CyclomaticComplexity
      case arg&.type
      when :sym then set << arg.children[0]
      when :array then arg.children.each { |c| collect_symbols(c, set) }
      when :hash
        arg.children.each do |pair|
          key = pair.children[0]
          set << key.children[0] if key&.type == :sym
          collect_symbols(pair.children[1], set)
        end
      end
    end

    def single_record?(node, var_values, depth = 0)
      return false if depth > 6 || !node.is_a?(Parser::AST::Node)

      case node.type
      when :send
        method = node.children[1]
        return true if SINGLE_RECORD_METHODS.include?(method)

        single_record?(node.children[0], var_values, depth + 1)
      when :array
        node.children.size == 1
      else
        false
      end
    end

    def walk(node, &block)
      return unless node.is_a?(Parser::AST::Node)

      yield node
      node.children.each { |c| walk(c, &block) }
    end
  end
end
