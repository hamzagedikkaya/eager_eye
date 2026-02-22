# frozen_string_literal: true

# Fixture: decorator N+1 bad examples
# These patterns should be detected by DecoratorNPlusOne detector

# Draper::Decorator style
class PostDecorator < Draper::Decorator
  delegate_all

  def comment_summary
    object.comments.map(&:body).join(", ") # N+1 — loads comments for each post
  end

  def tag_list
    object.tags.map(&:name).join(", ") # N+1 — loads tags for each post
  end

  def author_posts_count
    object.authors.size # N+1 — loads authors for each post
  end
end

# SimpleDelegator style
class OrderDecorator < SimpleDelegator
  def line_item_names
    __getobj__.items.map(&:name) # N+1 — loads items for each order
  end

  def product_skus
    __getobj__.products.map(&:sku) # N+1 — loads products for each order
  end
end

# Class name pattern — Presenter
class UserPresenter
  def recent_post_titles
    model.posts.last(5).map(&:title) # N+1 — loads posts for each user
  end

  def account_summary
    source.accounts.map(&:name) # N+1 — loads accounts for each user
  end
end

# Class name pattern — ViewObject
class InvoiceViewObject
  def customer_orders
    object.orders.map(&:total) # N+1 — loads orders for each invoice
  end
end
