# frozen_string_literal: true

RSpec.describe 'Glueby::Contract::TxBuilder' do
  class TxBuilderMock
    include Glueby::Contract::TxBuilder
  end

  let(:mock) { TxBuilderMock.new }
  let(:wallet) { TestWallet.new(internal_wallet) }
  let(:internal_wallet) { TestInternalWallet.new }
  let(:unspents) do
    [
      {
        txid: '5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5',
        script_pubkey: '76a914234113b860822e68f9715d1957af28b8f5117ee288ac',
        vout: 0,
        amount: 100_000_000,
        finalized: false
      }, {
        txid: '1d49c8038943d37c2723c9c7a1c4ea5c3738a9bad5827ddc41e144ba6aef36db',
        script_pubkey: '76a914234113b860822e68f9715d1957af28b8f5117ee288ac',
        vout: 1,
        amount: 100_000_000,
        finalized: true
      }, {
        txid: '1d49c8038943d37c2723c9c7a1c4ea5c3738a9bad5827ddc41e144ba6aef36db',
        script_pubkey: '76a914234113b860822e68f9715d1957af28b8f5117ee288ac',
        vout: 2,
        amount: 50_000_000,
        finalized: true
      }, {
        txid: '864247cd4cae4b1f5bd3901be9f7a4ccba5bdea7db1d8bbd78b944da9cf39ef5',
        vout: 0,
        script_pubkey: '21c3eb2b846463430b7be9962843a97ee522e3dc0994a0f5e2fc0aa82e20e67fe893bc76a914bfeca7aed62174a7c60ebc63c7bd797bad46157a88ac',
        color_id: 'c3eb2b846463430b7be9962843a97ee522e3dc0994a0f5e2fc0aa82e20e67fe893',
        amount: 1,
        finalized: true
      }, {
        txid: 'f14b29639483da7c8d17b7b7515da4ff78b91b4b89434e7988ab1bc21ab41377',
        vout: 0,
        script_pubkey: '21c2dbbebb191128de429084246fa3215f7ccc36d6abde62984eb5a42b1f2253a016bc76a914fc688c091d91789ccda7a27bd8d88be9ae4af58e88ac',
        color_id: 'c2dbbebb191128de429084246fa3215f7ccc36d6abde62984eb5a42b1f2253a016',
        amount: 100_000,
        finalized: true
      }, {
        txid: '100c4dc65ea4af8abb9e345b3d4cdcc548bb5e1cdb1cb3042c840e147da72fa2',
        vout: 0,
        script_pubkey: '21c150ad685ec8638543b2356cb1071cf834fb1c84f5fa3a71699c3ed7167dfcdbb3bc76a9144f15d2203821d7ea719314126b79bd1e530fc97588ac',
        color_id: 'c150ad685ec8638543b2356cb1071cf834fb1c84f5fa3a71699c3ed7167dfcdbb3',
        amount: 100_000,
        finalized: true
      }, {
        txid: 'a3f20bc94c8d77c35ba1770116d2b34375475a4194d15f76442636e9f77d50d9',
        vout: 2,
        script_pubkey: '21c150ad685ec8638543b2356cb1071cf834fb1c84f5fa3a71699c3ed7167dfcdbb3bc76a9144f15d2203821d7ea719314126b79bd1e530fc97588ac',
        color_id: 'c150ad685ec8638543b2356cb1071cf834fb1c84f5fa3a71699c3ed7167dfcdbb3',
        amount: 100_000,
        finalized: true
      }
    ]
  end

  before { allow(internal_wallet).to receive(:list_unspent).and_return(unspents) }

  describe '#create_funding_tx' do
    subject { mock.create_funding_tx(wallet: wallet) }

    it { expect(subject.inputs.size).to eq 1 }
    it { expect(subject.inputs[0].out_point.txid).to eq '5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5' }
    it { expect(subject.inputs[0].out_point.index).to eq 0 }
    it { expect(subject.outputs.size).to eq 2 }
    it { expect(subject.outputs[0].value).to eq 10_000 }
    it { expect(subject.outputs[1].value).to eq 99_980_000 }

    context 'use utxo provider', active_record: true do
      let(:utxo_provider) { Glueby::UtxoProvider.new }
      let(:wallet_adapter) { double(:wallet_adapter) }
      let(:utxo_provider_wallet) { TestInternalWallet.new }
      let(:pool_outputs) do
        (0...20).map do |i|
          {
            txid: '1d49c8038943d37c2723c9c7a1c4ea5c3738a9bad5827ddc41e144ba6aef36db',
            script_pubkey: '76a914234113b860822e68f9715d1957af28b8f5117ee288ac',
            vout: i,
            amount: 1_000,
            finalized: true
          }
        end
      end

      before do
        Glueby.configuration.enable_utxo_provider!
        Glueby::Internal::Wallet.wallet_adapter = wallet_adapter
        allow(wallet_adapter).to receive(:load_wallet)
        allow_any_instance_of(Glueby::UtxoProvider).to receive(:wallet).and_return(utxo_provider_wallet)
        allow(utxo_provider_wallet).to receive(:list_unspent).and_return(pool_outputs)
      end

      after do
        Glueby.configuration.disable_utxo_provider!
      end

      it { expect(subject.inputs.size).to eq 20 }
      it do
        expect(subject.inputs.map(&:out_point)).to contain_exactly(
          *(0...20).map do |i|
            Tapyrus::OutPoint.from_txid('1d49c8038943d37c2723c9c7a1c4ea5c3738a9bad5827ddc41e144ba6aef36db', i)
          end
        )
      end
      it { expect(subject.outputs.size).to eq 1 }
      it { expect(subject.outputs[0].value).to eq 10_000 }
    end
  end

  describe '#create_issue_tx_for_reissuable_token' do
    subject { mock.create_issue_tx_for_reissuable_token(funding_tx: funding_tx, issuer: issuer, amount: amount, split: split) }

    let(:funding_tx) do
      tx = Tapyrus::Tx.new
      tx.inputs << Tapyrus::TxIn.new(out_point: Tapyrus::OutPoint.from_txid('5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5', 0))
      tx.outputs << Tapyrus::TxOut.new(value: 100_000_000, script_pubkey: script_pubkey)
      tx
    end
    let(:script_pubkey) { Tapyrus::Script.parse_from_payload('76a914234113b860822e68f9715d1957af28b8f5117ee288ac'.htb) }
    let(:issuer) { wallet }
    let(:amount) { 1_000 }
    let(:split) { 1 }

    it { expect(subject.inputs.size).to eq 1 }
    it { expect(subject.inputs[0].out_point.txid).to eq funding_tx.txid }
    it { expect(subject.inputs[0].out_point.index).to eq 0 }
    it { expect(subject.outputs.size).to eq 2 }
    it { expect(subject.outputs[0].value).to eq 1_000 }
    it { expect(subject.outputs[0].colored?).to be_truthy }
    it { expect(subject.outputs[0].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
    it { expect(subject.outputs[1].value).to eq 99_990_000 }

    context 'split outputs' do
      let(:split) { 3 }
      it { expect(subject.outputs.size).to eq 4 }
      it { expect(subject.outputs[0].value).to eq 333 }
      it { expect(subject.outputs[0].colored?).to be_truthy }
      it { expect(subject.outputs[0].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
      it { expect(subject.outputs[1].value).to eq 333 }
      it { expect(subject.outputs[1].colored?).to be_truthy }
      it { expect(subject.outputs[1].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
      it { expect(subject.outputs[2].value).to eq 334 }
      it { expect(subject.outputs[2].colored?).to be_truthy }
      it { expect(subject.outputs[2].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
      it { expect(subject.outputs[3].value).to eq 99_990_000 }
      it { expect(subject.outputs[0].script_pubkey).to eq subject.outputs[1].script_pubkey }
      it { expect(subject.outputs[1].script_pubkey).to eq subject.outputs[2].script_pubkey }
    end
  end

  describe '#create_issue_tx_for_non_reissuable_token' do
    subject { mock.create_issue_tx_for_non_reissuable_token(issuer: issuer, amount: amount, split: split) }

    let(:issuer) { wallet }
    let(:amount) { 1_000 }
    let(:split) { 1 }

    it { expect(subject.inputs.size).to eq 1 }
    it { expect(subject.inputs[0].out_point.txid).to eq '5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5' }
    it { expect(subject.inputs[0].out_point.index).to eq 0 }
    it { expect(subject.outputs.size).to eq 2 }
    it { expect(subject.outputs[0].value).to eq 1_000 }
    it { expect(subject.outputs[0].colored?).to be_truthy }
    it { expect(subject.outputs[0].color_id.type).to eq Tapyrus::Color::TokenTypes::NON_REISSUABLE }
    it { expect(subject.outputs[1].value).to eq 99_990_000 }

    context 'split outputs' do
      let(:split) { 3 }

      it { expect(subject.outputs.size).to eq 4 }
      it { expect(subject.outputs[0].value).to eq 333 }
      it { expect(subject.outputs[0].colored?).to be_truthy }
      it { expect(subject.outputs[0].color_id.type).to eq Tapyrus::Color::TokenTypes::NON_REISSUABLE }
      it { expect(subject.outputs[1].value).to eq 333 }
      it { expect(subject.outputs[1].colored?).to be_truthy }
      it { expect(subject.outputs[1].color_id.type).to eq Tapyrus::Color::TokenTypes::NON_REISSUABLE }
      it { expect(subject.outputs[2].value).to eq 334 }
      it { expect(subject.outputs[2].colored?).to be_truthy }
      it { expect(subject.outputs[2].color_id.type).to eq Tapyrus::Color::TokenTypes::NON_REISSUABLE }
      it { expect(subject.outputs[3].value).to eq 99_990_000 }
      it { expect(subject.outputs[0].script_pubkey).to eq subject.outputs[1].script_pubkey }
      it { expect(subject.outputs[1].script_pubkey).to eq subject.outputs[2].script_pubkey }
    end
  end

  describe '#create_issue_tx_for_nft_token' do
    subject { mock.create_issue_tx_for_nft_token(issuer: issuer) }

    let(:issuer) { wallet }

    it { expect(subject.inputs.size).to eq 1 }
    it { expect(subject.inputs[0].out_point.txid).to eq '5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5' }
    it { expect(subject.inputs[0].out_point.index).to eq 0 }
    it { expect(subject.outputs.size).to eq 2 }
    it { expect(subject.outputs[0].value).to eq 1 }
    it { expect(subject.outputs[0].colored?).to be_truthy }
    it { expect(subject.outputs[0].color_id.type).to eq Tapyrus::Color::TokenTypes::NFT }
    it { expect(subject.outputs[1].value).to eq 99_990_000 }
  end

  describe '#create_reissue_tx' do
    subject { mock.create_reissue_tx(funding_tx: funding_tx, issuer: issuer, amount: amount, color_id: color_id, split: split) }

    let(:funding_tx) do
      tx = Tapyrus::Tx.new
      tx.inputs << Tapyrus::TxIn.new(out_point: Tapyrus::OutPoint.from_txid('5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5', 0))
      tx.outputs << Tapyrus::TxOut.new(value: 100_000_000, script_pubkey: script_pubkey)
      tx
    end
    let(:script_pubkey) { Tapyrus::Script.parse_from_payload('76a914234113b860822e68f9715d1957af28b8f5117ee288ac'.htb) }
    let(:issuer) { wallet }
    let(:amount) { 1_000 }
    let(:split) { 1 }
    let(:color_id) { Tapyrus::Color::ColorIdentifier.parse_from_payload('c185856a84c483fb108b1cdf79ff53aa7d54d1a137a5178684bd89ca31f906b2bd'.htb) }

    it { expect(subject.inputs.size).to eq 1 }
    it { expect(subject.inputs[0].out_point.txid).to eq funding_tx.txid }
    it { expect(subject.inputs[0].out_point.index).to eq 0 }
    it { expect(subject.outputs.size).to eq 2 }
    it { expect(subject.outputs[0].value).to eq 1_000 }
    it { expect(subject.outputs[0].colored?).to be_truthy }
    it { expect(subject.outputs[0].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }

    context 'split outputs' do
      let(:split) { 3 }

      it { expect(subject.outputs.size).to eq 4 }
      it { expect(subject.outputs[0].value).to eq 333 }
      it { expect(subject.outputs[0].colored?).to be_truthy }
      it { expect(subject.outputs[0].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
      it { expect(subject.outputs[1].value).to eq 333 }
      it { expect(subject.outputs[1].colored?).to be_truthy }
      it { expect(subject.outputs[1].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
      it { expect(subject.outputs[2].value).to eq 334 }
      it { expect(subject.outputs[2].colored?).to be_truthy }
      it { expect(subject.outputs[2].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
      it { expect(subject.outputs[3].value).to eq 99_990_000 }
      it { expect(subject.outputs[0].script_pubkey).to eq subject.outputs[1].script_pubkey }
      it { expect(subject.outputs[1].script_pubkey).to eq subject.outputs[2].script_pubkey }
    end
  end
  
  describe '#create_transfer_tx' do
    subject { mock.create_transfer_tx(color_id: color_id, sender: sender, receiver_address: receiver_address, amount: amount) }

    let(:color_id) { Tapyrus::Color::ColorIdentifier.parse_from_payload('c150ad685ec8638543b2356cb1071cf834fb1c84f5fa3a71699c3ed7167dfcdbb3'.htb) }
    let(:sender) { wallet }
    let(:receiver_address) { wallet.internal_wallet.receive_address }
    let(:script_pubkey) { Tapyrus::Script.parse_from_addr(receiver_address).add_color(color_id).to_hex }
    let(:amount) { 100_001 }

    it { expect(subject.inputs.size).to eq 3 }
    it { expect(subject.inputs[0].out_point.txid).to eq '100c4dc65ea4af8abb9e345b3d4cdcc548bb5e1cdb1cb3042c840e147da72fa2' }
    it { expect(subject.inputs[0].out_point.index).to eq 0 }
    it { expect(subject.inputs[1].out_point.txid).to eq 'a3f20bc94c8d77c35ba1770116d2b34375475a4194d15f76442636e9f77d50d9' }
    it { expect(subject.inputs[1].out_point.index).to eq 2 }
    it { expect(subject.inputs[2].out_point.txid).to eq '5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5' }
    it { expect(subject.inputs[2].out_point.index).to eq 0 }
    it { expect(subject.outputs.size).to eq 3 }
    it { expect(subject.outputs[0].value).to eq 100_001 }
    it { expect(subject.outputs[0].colored?).to be_truthy }
    it { expect(subject.outputs[0].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
    it { expect(subject.outputs[0].script_pubkey.to_hex).to eq script_pubkey }
    it { expect(subject.outputs[1].value).to eq 99_999 }
    it { expect(subject.outputs[1].colored?).to be_truthy }
    it { expect(subject.outputs[1].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
    it { expect(subject.outputs[2].value).to eq 99_990_000 }
  end

  describe '#create_multi_transfer_tx' do
    subject { mock.create_multi_transfer_tx(color_id: color_id, sender: sender, receivers: receivers) }

    let(:color_id) { Tapyrus::Color::ColorIdentifier.parse_from_payload('c150ad685ec8638543b2356cb1071cf834fb1c84f5fa3a71699c3ed7167dfcdbb3'.htb) }
    let(:sender) { wallet }
    let(:address1) { wallet.internal_wallet.receive_address }
    let(:address2) { wallet.internal_wallet.receive_address }
    let(:address3) { wallet.internal_wallet.receive_address }
    let(:script_pubkey1) { Tapyrus::Script.parse_from_addr(address1).add_color(color_id).to_hex }
    let(:script_pubkey2) { Tapyrus::Script.parse_from_addr(address2).add_color(color_id).to_hex }
    let(:script_pubkey3) { Tapyrus::Script.parse_from_addr(address3).add_color(color_id).to_hex }
    let(:receivers) do
      [
        { address: address1, amount: 100_001 },
        { address: address2, amount: 2 },
        { address: address3, amount: 3 }
      ]
    end

    it { expect(subject.inputs.size).to eq 3 }
    it { expect(subject.inputs[0].out_point.txid).to eq '100c4dc65ea4af8abb9e345b3d4cdcc548bb5e1cdb1cb3042c840e147da72fa2' }
    it { expect(subject.inputs[0].out_point.index).to eq 0 }
    it { expect(subject.inputs[1].out_point.txid).to eq 'a3f20bc94c8d77c35ba1770116d2b34375475a4194d15f76442636e9f77d50d9' }
    it { expect(subject.inputs[1].out_point.index).to eq 2 }
    it { expect(subject.inputs[2].out_point.txid).to eq '5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5' }
    it { expect(subject.inputs[2].out_point.index).to eq 0 }
    it { expect(subject.outputs.size).to eq 5 }
    it { expect(subject.outputs[0].value).to eq 100_001 }
    it { expect(subject.outputs[0].colored?).to be_truthy }
    it { expect(subject.outputs[0].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
    it { expect(subject.outputs[0].script_pubkey.to_hex).to eq script_pubkey1 }
    it { expect(subject.outputs[1].value).to eq 2 }
    it { expect(subject.outputs[1].colored?).to be_truthy }
    it { expect(subject.outputs[1].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
    it { expect(subject.outputs[1].script_pubkey.to_hex).to eq script_pubkey2 }
    it { expect(subject.outputs[2].value).to eq 3 }
    it { expect(subject.outputs[2].colored?).to be_truthy }
    it { expect(subject.outputs[2].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
    it { expect(subject.outputs[2].script_pubkey.to_hex).to eq script_pubkey3 }
    it { expect(subject.outputs[3].value).to eq 99_994 }
    it { expect(subject.outputs[3].colored?).to be_truthy }
    it { expect(subject.outputs[3].color_id.type).to eq Tapyrus::Color::TokenTypes::REISSUABLE }
    it { expect(subject.outputs[4].value).to eq 99_990_000 }
  end

  describe '#create_burn_tx' do
    subject { mock.create_burn_tx(color_id: color_id, sender: sender, amount: amount, fee_estimator: fee_estimator) }

    let(:color_id) { Tapyrus::Color::ColorIdentifier.parse_from_payload('c150ad685ec8638543b2356cb1071cf834fb1c84f5fa3a71699c3ed7167dfcdbb3'.htb) }
    let(:sender) { wallet }
    let(:amount) { 50_000 }
    let(:fee_estimator) { Glueby::Contract::FixedFeeEstimator.new }

    it { expect(subject.inputs.size).to eq 2 }
    it { expect(subject.inputs[0].out_point.txid).to eq '100c4dc65ea4af8abb9e345b3d4cdcc548bb5e1cdb1cb3042c840e147da72fa2' }
    it { expect(subject.inputs[0].out_point.index).to eq 0 }
    it { expect(subject.inputs[1].out_point.txid).to eq '5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5' }
    it { expect(subject.inputs[1].out_point.index).to eq 0 }
    it { expect(subject.outputs.size).to eq 2 }
    it { expect(subject.outputs[0].value).to eq 50_000 }
    it { expect(subject.outputs[0].colored?).to be_truthy }
    it { expect(subject.outputs[1].value).to eq 99_990_000 }
    it { expect(subject.outputs[1].colored?).to be_falsy }

    context 'if specified amount is 0' do
      let(:amount) { 0 }

      it { expect(subject.outputs.size).to eq 1 }
      it { expect(subject.outputs[0].value).to eq 99_990_000 }
      it { expect(subject.outputs[0].colored?).to be_falsy }
    end

    context 'tx fee is same as value of the first utxo' do
      let(:fee_estimator) { Glueby::Contract::FixedFeeEstimator.new(fixed_fee: 100_000_000) }
      let(:amount) { 0 }

      it 'should have at least one output' do
        expect(subject.inputs.size).to eq 4
        expect(subject.inputs[0].out_point.txid).to eq '100c4dc65ea4af8abb9e345b3d4cdcc548bb5e1cdb1cb3042c840e147da72fa2'
        expect(subject.inputs[0].out_point.index).to eq 0
        expect(subject.inputs[1].out_point.txid).to eq 'a3f20bc94c8d77c35ba1770116d2b34375475a4194d15f76442636e9f77d50d9'
        expect(subject.inputs[1].out_point.index).to eq 2
        expect(subject.inputs[2].out_point.txid).to eq '5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5'
        expect(subject.inputs[2].out_point.index).to eq 0
        expect(subject.inputs[3].out_point.txid).to eq '1d49c8038943d37c2723c9c7a1c4ea5c3738a9bad5827ddc41e144ba6aef36db'
        expect(subject.inputs[3].out_point.index).to eq 1
        expect(subject.outputs.size).to eq 1
        expect(subject.outputs[0].value).to eq 100_000_000
        expect(subject.outputs[0].colored?).to be_falsy
      end
    end
  end

  describe '#add_split_output' do
    subject { mock.add_split_output(tx, amount, split, script_pubkey) }

    let(:tx) { Tapyrus::Tx.new }
    let(:amount) { 10001 }
    let(:split) { 1 }
    let(:script_pubkey) { Tapyrus::Script.new }

    it do
      subject 
      expect(tx.outputs.size).to eq 1
      expect(tx.outputs[0].value).to eq 10001
      expect(tx.outputs[0].script_pubkey.to_hex).to eq script_pubkey.to_hex
    end

    context 'split 100 outputs' do
      let(:split) { 100 }

      it do
        subject 
        expect(tx.outputs.size).to eq 100
        expect(tx.outputs[0].value).to eq 100
        expect(tx.outputs[0].script_pubkey.to_hex).to eq script_pubkey.to_hex
        expect(tx.outputs[99].value).to eq 101
        expect(tx.outputs[99].script_pubkey.to_hex).to eq script_pubkey.to_hex
      end
    end

    context 'amount is less than split parameter' do
      let(:amount) { 10 }
      let(:split) { 100 }

      it do
        subject 
        expect(tx.outputs.size).to eq 10
        expect(tx.outputs[0].value).to eq 1
        expect(tx.outputs[0].script_pubkey.to_hex).to eq script_pubkey.to_hex
        expect(tx.outputs[9].value).to eq 1
        expect(tx.outputs[9].script_pubkey.to_hex).to eq script_pubkey.to_hex
      end
    end

    context 'The amount is divisible by split.' do
      let(:amount) { 999 }
      let(:split) { 3 }

      it do
        subject 
        expect(tx.outputs.size).to eq 3
        expect(tx.outputs[0].value).to eq 333
        expect(tx.outputs[0].script_pubkey.to_hex).to eq script_pubkey.to_hex
        expect(tx.outputs[1].value).to eq 333
        expect(tx.outputs[1].script_pubkey.to_hex).to eq script_pubkey.to_hex
        expect(tx.outputs[2].value).to eq 333
        expect(tx.outputs[2].script_pubkey.to_hex).to eq script_pubkey.to_hex
      end
    end
  end
  describe '#fill_input' do
    subject { mock.fill_input(tx, outputs) }

    let(:tx) { Tapyrus::Tx.new }
    let(:outputs) { unspents }

    it { expect { subject }.to change { tx.inputs.size }.from(0).to(7) }
  end

  describe '#fill_change_tpc' do
    subject { mock.fill_change_tpc(tx, wallet, amount) }
    let(:tx) { Tapyrus::Tx.new }
    let(:amount) { 1 }

    it { expect { subject }.to change { tx.outputs.size }.from(0).to(1) }

    context 'if change is 0' do
      let(:amount) { 0 }

      it { expect { subject }.not_to change { tx.outputs.size } }
    end
  end

  describe '#fill_change_token' do
    subject { mock.fill_change_token(tx, wallet, amount, color_id) }

    let(:tx) { Tapyrus::Tx.new }
    let(:amount) { 1 }
    let(:color_id) { Tapyrus::Color::ColorIdentifier.parse_from_payload('c3eb2b846463430b7be9962843a97ee522e3dc0994a0f5e2fc0aa82e20e67fe893'.htb) }

    it { expect { subject }.to change { tx.outputs.size }.from(0).to(1) }

    context 'if change is 0' do
      let(:amount) { 0 }

      it { expect { subject }.not_to change { tx.outputs.size } }
    end
  end

  describe '#collect_colored_outputs' do
    subject { mock.collect_colored_outputs(results, color_id, amount) }

    let(:results) { unspents }
    let(:amount) { 50_000 }
    let(:color_id) { Tapyrus::Color::ColorIdentifier.parse_from_payload('c150ad685ec8638543b2356cb1071cf834fb1c84f5fa3a71699c3ed7167dfcdbb3'.htb) }

    it { expect(subject[0]).to eq 100_000 }
    it { expect(subject[1].size).to eq 1 }

    context 'does not have enough token' do
      let(:amount) { 200_001 }

      it { expect { subject }.to raise_error Glueby::Contract::Errors::InsufficientTokens }
    end

    context 'if specified amount is 0' do
      let(:amount) { 0 }

      it 'should return all outputs which has the color_id' do
        expect(subject[0]).to eq 200_000
        expect(subject[1].size).to eq 2
      end
    end
  end

  describe '#dummy_tx' do
    subject { mock.dummy_tx(Tapyrus::Tx.new) }

    it { expect(subject.inputs.size).to eq 1 }
    it { expect(subject.outputs.size).to eq 1 }
  end

  describe '#dummy_issue_tx_from_out_point' do
    subject { mock.dummy_issue_tx_from_out_point }

    it { expect(subject.inputs.size).to eq 1 }
    it { expect(subject.outputs.size).to eq 2 }
    it { expect(subject.outputs[0].colored?).to be_truthy }
    it { expect(subject.outputs[1].colored?).to be_falsy }
  end
end
