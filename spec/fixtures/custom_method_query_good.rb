# frozen_string_literal: true

class OrderProcessor
  def process_all
    # Preload outside loop
    orders_with_associations = @orders.includes(:coupons, :line_items, :products, :items)

    orders_with_associations.each do |order|
      # OK: filtering loaded association in Ruby
      discount = order.coupons.find(&:active?)
      has_warranty = order.line_items.any?(&:warranty?)
      featured = order.products.find(&:featured?)
      ids = order.items.map(&:id)

      process_order(order, discount, has_warranty, featured, ids)
    end
  end

  def check_support
    # Preload teams and filter in Ruby
    @users.includes(:teams).map do |user|
      user.teams.any? { |t| t.name == "Lakers" }
    end
  end

  def calculate_totals
    # Use Ruby enumerable methods on preloaded associations
    orders_with_items = @orders.includes(:line_items)

    orders_with_items.each do |order|
      # OK: Ruby sum on array
      _total = order.line_items.sum(&:price)

      # OK: Ruby count on array
      _item_count = order.line_items.size

      # OK: Ruby max on array
      _max_price = order.line_items.map(&:price).max
    end
  end

  private

  def process_order(order, discount, has_warranty, featured, ids)
    # processing logic
  end
end
