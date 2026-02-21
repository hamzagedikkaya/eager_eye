# frozen_string_literal: true

# Fixture: delegation N+1 bad examples
# These patterns should be detected by DelegationNPlusOne detector

class Order < ApplicationRecord
  belongs_to :user
  belongs_to :shipping_address
  delegate :full_name, :email, to: :user
  delegate :street, to: :shipping_address
end

# Bad: delegated methods called inside loop without includes
orders.each do |order|
  order.full_name  # N+1 — delegated to :user
  order.email      # N+1 — delegated to :user
  order.street     # N+1 — delegated to :shipping_address
end

class Post < ApplicationRecord
  belongs_to :author
  belongs_to :category
  delegate :bio, :avatar_url, to: :author
  delegate :label, to: :category
end

# Bad: multiple delegations to different associations
posts.map do |post|
  post.bio # N+1 — delegated to :author
  post.avatar_url # N+1 — delegated to :author
  post.label # N+1 — delegated to :category
end

class Invoice < ApplicationRecord
  belongs_to :customer
  delegate :company_name, :vat_number, to: :customer
end

# Bad: delegation in flat_map
invoices.flat_map(&:company_name)
