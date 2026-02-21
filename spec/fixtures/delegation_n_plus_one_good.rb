# frozen_string_literal: true

# Fixture: delegation N+1 good examples
# These patterns should NOT be detected by DelegationNPlusOne detector

class Order < ApplicationRecord
  belongs_to :user
  belongs_to :shipping_address
  delegate :full_name, :email, to: :user
  delegate :street, to: :shipping_address
end

# Good: association preloaded with includes
orders.includes(:user, :shipping_address).each do |order|
  order.full_name  # no N+1 — user is included
  order.email      # no N+1 — user is included
  order.street     # no N+1 — shipping_address is included
end

class Post < ApplicationRecord
  belongs_to :author
  delegate :bio, to: :author
end

# Good: preload via preload method
posts.preload(:author).each(&:bio)

# Good: preload via eager_load
Post.eager_load(:author).each(&:bio)

# Good: non-delegated regular attribute calls (should never be flagged)
orders.each do |order|
  order.id
  order.created_at
  order.status
end
