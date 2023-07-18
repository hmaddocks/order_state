# frozen_string_literal: true

# require 'active_record'
class Order # < ActiveRecord::Base
  include OrderState

  attr_accessor :state

  def initialize
    @state = "received"
  end

  # Query the state
  def active?
    order_state.active?
  end

  # Predicates used by the states to determine if the state can transition
  def can_confirm?
    true
  end

  def can_complete?
    true
  end

  def can_ship?
    true
  end

  # predicates using the order state
  def can_add_item?
    order_state.received?
  end

  def can_edit?
    order_state.can_edit?
  end

  def can_cancel?
    order_state.can_cancel?
  end

  # Actions. These will fail if the order is in the wrong state
  def cancel!
    Order.transaction do
      order_state.cancel! do
        cancel_production_entries
      end
    end
  end

  def close!
    Order.transaction do
      order_state.close! do
        production_entries.each(&:consume!)
      end
    end
  end
end
