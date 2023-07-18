# frozen_string_literal: true

require_relative 'spec_helper'
require_relative 'order_state'
require_relative 'order'

describe 'OrderState' do
  let(:time) { Time.new(1993, 0o2, 24, 12, 0, 0, '+09:00') }
  let(:stateful) do
    double('stateful')
  end

  describe 'Instantiate the correct state.' do
    subject { OrderState.get_state(stateful) }

    let(:stateful) do
      double('stateful', state: 'closed')
    end

    it 'instantiate the correct state class' do
      expect(subject.class).to eq OrderState::Released
    end
  end

  describe 'Raise helpful message for invalid state' do
    subject { -> { OrderState.get_state(stateful) } }

    let(:stateful) do
      double('stateful', state: 'invalid')
    end

    it { is_expected.to raise_error(/Invalid State 'invalid'/) }
  end

  describe "Base class doesn't do much" do
    subject { OrderState::Base.new(stateful) }

    let(:stateful) { Struct.new(:state).new('test') }

    %i[add_part! confirm! release! start! complete! ship! close! cancel!].each do |action|
      it { expect { subject.public_send action }.to raise_error(/Can't #{action} from 'test' state/) }
    end
  end

  describe OrderState::Received do
    subject { described_class.new(stateful) }

    it { is_expected.to be_received }
    it { is_expected.to be_can_cancel }
    it { is_expected.to be_active }

    describe '#confirm!' do
      subject { described_class.new(stateful).confirm!(time) }

      let(:stateful) do
        double('stateful', state: 'received')
      end

      context 'when can confirm' do
        before do
          allow(stateful).to receive(:can_confirm?).and_return(true)
        end

        it 'set the state to confirmed' do
          expect(stateful).to receive(:update!).with(state: 'confirmed', confirmed_at: time)
          subject
        end
      end

      context "when can't confirm" do
        before do
          allow(stateful).to receive(:can_confirm?).and_return(false)
        end

        it 'keep the state as received' do
          expect(stateful).not_to receive(:update!)
          expect { subject }.to raise_error(/Can't confirm! from 'received' state/)
        end
      end
    end

    describe '#cancel!' do
      subject { described_class.new(stateful).cancel!(time) }

      it 'set the state to cancelled' do
        expect(stateful).to receive(:update!).with(state: 'cancelled', cancelled_at: time)
        subject
      end
    end
  end

  describe OrderState::Confirmed do
    subject { described_class.new(stateful) }

    it { is_expected.to be_can_cancel }
    it { is_expected.to be_active }

    describe '#release!' do
      subject { described_class.new(stateful).release!(time) {} }

      it 'set the state to released' do
        allow(stateful).to receive(:can_ship?)
        allow(stateful).to receive(:can_complete?)
        expect(stateful).to receive(:update!).with(state: 'released', released_at: time)
        subject
      end
    end

    describe '#cancel!' do
      subject { described_class.new(stateful).cancel!(time) }

      it 'set the state to cancelled' do
        expect(stateful).to receive(:update!).with(state: 'cancelled', cancelled_at: time)
        subject
      end
    end
  end

  describe OrderState::Released do
    subject { described_class.new(stateful) }

    it { is_expected.to be_can_cancel }
    it { is_expected.to be_active }

    describe '#start!' do
      subject { described_class.new(stateful).start!(time) }

      context "when order hasn't started" do
        it 'set the state to started' do
          allow(stateful).to receive(:can_ship?)
          allow(stateful).to receive(:can_complete?)
          expect(stateful).to receive(:update!).with(state: 'in_progress', started_at: time)
          subject
        end
      end
    end

    describe '#cancel!' do
      subject { described_class.new(stateful).cancel!(time) }

      it 'set the state to cancelled' do
        expect(stateful).to receive(:update!).with(state: 'cancelled', cancelled_at: time)
        subject
      end
    end
  end

  describe OrderState::InProgress do
    subject { described_class.new(stateful) }

    it { is_expected.to be_can_cancel }
    it { is_expected.to be_active }

    describe '#start!' do
      context 'when order has already started' do
        subject { described_class.new(stateful).start! }

        it "Don't do anything" do
          expect(stateful).not_to receive(:update!)
          subject
        end
      end
    end

    describe '#make_shippable!' do
      subject { described_class.new(stateful).make_shippable!(time) }

      let(:stateful) do
        double('stateful', state: 'in_progress')
      end

      context "when can't ship" do
        before do
          allow(stateful).to receive(:can_complete?).and_return(false)
          allow(stateful).to receive(:can_ship?).and_return(false)
        end

        it "don't change state" do
          expect(stateful).not_to receive(:update!)
          subject
        end
      end

      context "when can't complete but can ship" do
        before do
          allow(stateful).to receive(:can_complete?).and_return(false)
          allow(stateful).to receive(:can_ship?).and_return(true)
        end

        it 'stateful can be ready to ship' do
          expect(stateful).to receive(:update!).with(state: 'ready_to_ship')
          subject
        end
      end

      context 'when can complete' do
        before do
          allow(stateful).to receive(:can_complete?).and_return(true)
        end

        it 'set the state to shipped' do
          expect(stateful).to receive(:update!).with(state: 'shipped', completed_at: time)
          subject
        end
      end
    end

    describe '#complete!' do
      subject { described_class.new(stateful).complete!(time) }

      let(:stateful) do
        double('stateful', state: 'in_progress')
      end

      context 'when when oan complete' do
        before do
          allow(stateful).to receive(:can_complete?).and_return(true)
        end

        it 'set the state to shipped' do
          expect(stateful).to receive(:update!).with(state: 'shipped', completed_at: time)
          subject
        end
      end

      context "when when oan't complete" do
        before do
          allow(stateful).to receive(:can_complete?).and_return(false)
        end

        it "don't change the state" do
          expect(stateful).not_to receive(:update!)
        end
      end
    end
  end

  describe OrderState::ReadyToShip do
    describe '#start!' do
      context 'when the order has already started' do
        subject { described_class.new(stateful).start! }

        it "Don't do anything" do
          expect(stateful).not_to receive(:update!)
          subject
        end
      end
    end

    describe '#make_shippable!' do
      subject { described_class.new(stateful).make_shippable!(time) }

      context "when order can't complete" do
        before do
          allow(stateful).to receive(:can_complete?).and_return(false)
        end

        it "don't change the state" do
          expect(stateful).not_to receive(:update!)
        end
      end

      context 'when order can be completed' do
        before do
          allow(stateful).to receive(:can_complete?).and_return(true)
        end

        it 'set the state to shipped' do
          expect(stateful).to receive(:update!).with(state: 'shipped', completed_at: time)
          subject
        end
      end
    end

    describe '#ship!' do
      subject { described_class.new(stateful).ship!(time) }

      before { allow(stateful).to receive(:reload) }

      let(:stateful) do
        double('stateful', state: 'ready_to_ship')
      end

      context 'when can complete' do
        before do
          allow(stateful).to receive(:can_complete?).and_return(true)
        end

        it 'set the state to shipped' do
          expect(stateful).to receive(:update!).with(state: 'shipped', completed_at: time)
          subject
        end
      end

      context "when chen can't complete" do
        before do
          allow(stateful).to receive(:can_complete?).and_return(false)
        end

        it 'set the state to in_progress' do
          expect(stateful).to receive(:update!).with(state: 'in_progress')
          subject
        end
      end
    end

    describe '#complete!' do
      subject { described_class.new(stateful).complete!(time) }

      let(:stateful) do
        double('stateful', state: 'ready_to_ship')
      end

      context 'when can complete' do
        before do
          allow(stateful).to receive(:can_complete?).and_return(true)
        end

        it 'set the state to shipped' do
          expect(stateful).to receive(:update!).with(state: 'shipped', completed_at: time)
          subject
        end
      end

      context "when can't complete" do
        before do
          allow(stateful).to receive(:can_complete?).and_return(false)
        end

        it "don't change the state" do
          expect(stateful).not_to receive(:update!)
        end
      end
    end
  end

  describe OrderState::Shipped do
    subject { described_class.new(stateful) }

    it { is_expected.not_to be_can_cancel }
    it { is_expected.to be_active }

    describe '#close!' do
      subject { described_class.new(stateful).close!(time) }

      let(:stateful) do
        double('stateful', state: 'shipped')
      end

      it 'set the state to closed' do
        expect(stateful).to receive(:update!).with(state: 'closed', closed_at: time)
        subject
      end
    end
  end

  describe '#cancel!' do
    context 'when in a state that can be cancelled' do
      subject { OrderState::InProgress.new(stateful).cancel!(time) }

      it 'set the state to cancelled' do
        expect(stateful).to receive(:update!).with(state: 'cancelled', cancelled_at: time)
        subject
      end
    end

    context "when in a state that can't be cancelled" do
      subject { OrderState::Shipped.new(stateful).cancel! }

      let(:stateful) do
        double('stateful', state: 'shipped')
      end

      it { expect { subject }.to raise_error(/Can't cancel! from 'shipped' state/) }
    end
  end

  describe OrderState::Closed do
    subject { described_class.new(stateful) }

    it { is_expected.not_to be_can_cancel }
  end

  describe OrderState::Cancelled do
    subject { described_class.new(stateful) }

    it { is_expected.not_to be_active }
  end
end
