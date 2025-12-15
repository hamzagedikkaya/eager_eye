# frozen_string_literal: true

class OrderProcessor
  def process_all
    @orders.each do |order|
      # BAD: where inside loop
      discount = order.coupons.where(active: true).first

      # BAD: exists? inside loop
      has_warranty = order.line_items.where(warranty: true).exists?

      # BAD: find_by inside loop
      featured = order.products.find_by(featured: true)

      # BAD: pluck inside loop
      ids = order.items.pluck(:id)

      process_order(order, discount, has_warranty, featured, ids)
    end
  end

  def check_support
    @users.map do |user|
      user.teams.where(name: "Lakers").exists?
    end
  end

  def calculate_totals
    @orders.each do |order|
      # BAD: sum inside loop
      _total = order.line_items.sum(:price)

      # BAD: count inside loop
      _item_count = order.line_items.count

      # BAD: maximum inside loop
      _max_price = order.line_items.maximum(:price)
    end
  end

  private

  def process_order(order, discount, has_warranty, featured, ids)
    # processing logic
  end
end
