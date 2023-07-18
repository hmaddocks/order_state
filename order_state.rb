# frozen_string_literal: true

module OrderState
  StateError = Class.new(StandardError)

  STATES = %w[received confirmed released in_progress ready_to_ship shipped closed cancelled].freeze

  def self.included(base)
    base.class_eval do
      # ActiveRecord
      # validates_inclusion_of :state, in: STATES

      STATES.each do |state|
        define_singleton_method state do
          where(state: state)
        end
      end
    end
  end

  def order_state
    OrderState.get_state(self)
  end

  def self.get_state(stateful)
    "order_state/#{stateful.state}".camelize.constantize.new stateful
  rescue NameError
    raise StateError, "Invalid State '#{stateful.state}'"
  end

  ACTIONS = %i[received? add_part! confirm! confirmed? release! released? start! make_shippable! complete! ship!
               shipped? close! closed? cancel! cancelled?].freeze

  ACTIONS.each do |action|
    define_method action do
      order_state.public_send action
    end
  end

  class Base
    def initialize(stateful)
      @stateful = stateful
    end

    OrderState::ACTIONS.each do |action|
      if action[-1] == '!'
        define_method action do
          raise StateError, "#{@stateful.class.name}: Can't #{action} from '#{@stateful.state}' state"
        end
      else
        define_method(action) { false }
      end
    end

    def confirm!(_time = Time.now)
      raise StateError, "Can't confirm! from '#{@stateful.state}' state"
    end

    def can_edit?
      true
    end

    def can_cancel?
      false
    end

    def active?
      true
    end
  end

  class Cancellable < Base
    def cancel!(time = Time.zone.now)
      yield if block_given?
      @stateful.update!(state: 'cancelled', cancelled_at: time)
    end

    def can_cancel?
      true
    end
  end

  class Received < Cancellable
    def received?
      true
    end

    def add_part!
      yield if block_given?
    end

    def confirm!(time = Time.zone.now)
      super unless @stateful.can_confirm?
      yield if block_given?
      @stateful.update!(state: 'confirmed', confirmed_at: time)
    end
  end

  class Confirmed < Cancellable
    def release!(time = Time.zone.now)
      yield if block_given?

      if @stateful.can_ship?
        @stateful.update!(state: 'ready_to_ship', started_at: time)
      elsif @stateful.can_complete?
        @stateful.update!(state: 'shipped', started_at: time, completed_at: time)
      else
        @stateful.update!(state: 'released', released_at: time)
      end
    end

    def confirmed?
      true
    end
  end

  class Released < Cancellable
    def start!(time = Time.zone.now)
      yield if block_given?

      if @stateful.can_ship?
        @stateful.update!(state: 'ready_to_ship')
      elsif @stateful.can_complete?
        @stateful.update!(state: 'shipped', completed_at: time)
      else
        @stateful.update!(state: 'in_progress', started_at: time)
      end
    end

    def released?
      true
    end
  end

  class InProgress < Cancellable
    def start!; end

    def make_shippable!(time = Time.zone.now)
      yield if block_given?

      if @stateful.can_complete?
        @stateful.update!(state: 'shipped', completed_at: time)
      elsif @stateful.can_ship?
        @stateful.update!(state: 'ready_to_ship')
      end
    end

    def complete!(time = Time.zone.now)
      retrun unless @stateful.can_complete?

      yield if block_given?
      @stateful.update!(state: 'shipped', completed_at: time)
    end
  end

  class ReadyToShip < Cancellable
    def start!; end

    def make_shippable!(time = Time.zone.now)
      yield if block_given?

      @stateful.update!(state: 'shipped', completed_at: time) if @stateful.can_complete?
    end

    def ship!(time = Time.zone.now)
      result = yield if block_given?

      # Needs this to pickup the production entry state changes for @stateful.can_complete?
      @stateful.reload

      if @stateful.can_complete?
        @stateful.update!(state: 'shipped', completed_at: time)
      else
        @stateful.update!(state: 'in_progress')
      end
      result
    end

    def complete!(time = Time.zone.now)
      return unless @stateful.can_complete?

      yield if block_given?
      @stateful.update!(state: 'shipped', completed_at: time)
    end
  end

  class Shipped < Base
    def close!(time = Time.zone.now)
      yield if block_given?
      @stateful.update!(state: 'closed', closed_at: time)
    end

    def shipped?
      true
    end

    def can_edit?
      false
    end
  end

  class Closed < Base
    def active?
      false
    end

    def can_edit?
      false
    end

    def closed?
      true
    end
  end

  class Cancelled < Base
    def cancelled?
      true
    end

    def active?
      false
    end

    def can_edit?
      false
    end
  end
end
