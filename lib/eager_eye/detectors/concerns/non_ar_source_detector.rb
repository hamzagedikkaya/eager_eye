# frozen_string_literal: true

module EagerEye
  module Detectors
    module Concerns
      module NonArSourceDetector
        NON_AR_RECEIVERS = %w[Sidekiq Redis Resque DelayedJob Queue Job Hash Array Set].freeze
        NON_DB_SOURCE_METHODS = %i[smembers sinter sunion sdiff zrange zrangebyscore lrange hkeys hvals hgetall
                                   keys values entries args].freeze

        private

        def ar_receiver?(node)
          receiver = node.children[0]
          return true unless receiver.is_a?(Parser::AST::Node)

          !non_ar_class?(receiver)
        end

        def non_ar_class?(node)
          return false unless node.is_a?(Parser::AST::Node)
          return NON_AR_RECEIVERS.any? { |r| extract_const_name(node).include?(r) } if node.type == :const
          return non_ar_class?(node.children[0]) if node.type == :send && node.children[0].is_a?(Parser::AST::Node)

          false
        end

        def extract_const_name(node)
          return "" unless node.is_a?(Parser::AST::Node) && node.type == :const

          parent_name = extract_const_name(node.children[0])
          name = node.children[1].to_s
          parent_name.empty? ? name : "#{parent_name}::#{name}"
        end

        def non_db_source?(node)
          return false unless node.is_a?(Parser::AST::Node)
          return false unless %i[send block].include?(node.type)

          send_node = node.type == :block ? node.children[0] : node
          send_node.is_a?(Parser::AST::Node) && non_db_method_chain?(send_node)
        end

        def non_db_method_chain?(node)
          return false unless node.is_a?(Parser::AST::Node) && node.type == :send
          return true if NON_DB_SOURCE_METHODS.include?(node.children[1])

          receiver = node.children[0]
          return non_ar_class?(receiver) || non_db_method_chain?(receiver) if receiver.is_a?(Parser::AST::Node)

          false
        end
      end
    end
  end
end
