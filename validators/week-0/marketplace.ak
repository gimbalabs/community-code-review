
use cardano/address.{Address}
use cardano/assets.{add, from_lovelace, lovelace_of}
use cardano/transaction.{
  InlineDatum, Input, OutputReference, Transaction, find_input,
}
use cocktail.{
  address_pub_key, get_all_value_to, inputs_at, key_signed, value_geq,
}
use mocktail.{
  add_input, complete, mock_policy_id, mock_pub_key_address, mock_pub_key_hash,
  mock_script_address, mock_script_output, mock_tx_hash, mock_utxo_ref,
  mocktail_tx, required_signer_hash, tx_in, tx_in_inline_datum, tx_out,
}

pub type MarketplaceDatum {
  MarketplaceDatum {
    seller: Address,
    price: Int,
    policy: ByteArray,
    tokenName: ByteArray,
  }
}

pub type MarketplaceRedeemer {
  Buy
  Close
}

validator marketplace(owner: Address, fee_percentage_basis_point: Int) {
  spend(
    datum_opt: Option<MarketplaceDatum>,
    redeemer: MarketplaceRedeemer,
    input: OutputReference,
    tx: Transaction,
  ) {
    expect Some(datum) = datum_opt
    when redeemer is {
      Buy -> {
        expect Some(own_input) = find_input(tx.inputs, input)
        let own_address = own_input.output.address
        let is_only_one_input_from_own_address =
          when inputs_at(tx.inputs, own_address) is {
            [_] -> True
            _ -> False
          }
        let is_proceed_paid =
          get_all_value_to(tx.outputs, datum.seller)
            |> value_geq(
                from_lovelace(datum.price + lovelace_of(own_input.output.value)),
              )
        let is_fee_paid =
          get_all_value_to(tx.outputs, owner)
            |> value_geq(
                from_lovelace(datum.price * fee_percentage_basis_point / 10000),
              )
        is_only_one_input_from_own_address && is_fee_paid && is_proceed_paid
      }
      Close -> {
        expect Some(pub_key) = address_pub_key(datum.seller)
        key_signed(tx.extra_signatories, pub_key)
      }
    }
  }

  else(_) {
    fail
  }
}

// tests

type CloseTestCase {
  is_seller_signed: Bool,
}

fn mock_datum() -> MarketplaceDatum {
  MarketplaceDatum {
    seller: mock_pub_key_address(1, None),
    price: 200_000_000,
    policy: mock_policy_id(0),
    tokenName: "Test Token",
  }
}

fn get_close_test_tx(test_case: CloseTestCase) -> Transaction {
  let CloseTestCase { is_seller_signed } = test_case

  mocktail_tx()
    |> tx_in(
        True,
        mock_tx_hash(0),
        1,
        from_lovelace(2_000_000),
        mock_script_address(0, None),
      )
    |> tx_in_inline_datum(True, mock_datum())
    |> required_signer_hash(is_seller_signed, mock_pub_key_hash(1))
    |> complete()
}

test success_spend_marketplace_close() {
  let output_reference = mock_utxo_ref(0, 1)
  let redeemer = Close
  let test_case = CloseTestCase { is_seller_signed: True }

  let tx = get_close_test_tx(test_case)
  marketplace.spend(
    mock_pub_key_address(0, None),
    100,
    Some(mock_datum()),
    redeemer,
    output_reference,
    tx,
  )
}

test fail_spend_marketplace_close_without_signature() {
  let output_reference = mock_utxo_ref(0, 1)
  let redeemer = Close
  let test_case = CloseTestCase { is_seller_signed: False }

  let tx = get_close_test_tx(test_case)
  !marketplace.spend(
    mock_pub_key_address(0, None),
    100,
    Some(mock_datum()),
    redeemer,
    output_reference,
    tx,
  )
}

type BuyTestCase {
  is_only_one_input_from_script: Bool,
  is_fee_paid: Bool,
  is_proceed_paid: Bool,
}

fn get_buy_test_tx(test_case: BuyTestCase) -> Transaction {
  let BuyTestCase {
    is_only_one_input_from_script,
    is_fee_paid,
    is_proceed_paid,
  } = test_case

  let input_value =
    from_lovelace(2_000_000) |> add(mock_policy_id(0), "Test Token", 1)

  mocktail_tx()
    |> tx_out(
        True,
        mock_pub_key_address(0, None),
        if is_fee_paid {
          from_lovelace(2_000_000)
        } else {
          from_lovelace(1_000_000)
        },
      )
    |> tx_out(
        True,
        mock_pub_key_address(1, None),
        if is_proceed_paid {
          from_lovelace(202_000_000)
        } else {
          from_lovelace(200_000_000)
        },
      )
    |> complete()
    |> add_input(
        True,
        Input {
          output_reference: mock_utxo_ref(0, 1),
          output: mock_script_output(
            mock_script_address(0, None),
            input_value,
            InlineDatum(Some(mock_datum())),
          ),
        },
      )
    |> add_input(
        !is_only_one_input_from_script,
        Input {
          output_reference: mock_utxo_ref(0, 2),
          output: mock_script_output(
            mock_script_address(0, None),
            input_value,
            InlineDatum(Some(mock_datum())),
          ),
        },
      )
}

test success_spend_marketplace_buy() {
  let output_reference = mock_utxo_ref(0, 1)
  let redeemer = Buy
  let test_case =
    BuyTestCase {
      is_only_one_input_from_script: True,
      is_fee_paid: True,
      is_proceed_paid: True,
    }

  let tx = get_buy_test_tx(test_case)
  marketplace.spend(
    mock_pub_key_address(0, None),
    100,
    Some(mock_datum()),
    redeemer,
    output_reference,
    tx,
  )
}

test fail_spend_marketplace_buy_with_multiple_script_inputs() {
  let output_reference = mock_utxo_ref(0, 1)
  let redeemer = Buy
  let test_case =
    BuyTestCase {
      is_only_one_input_from_script: False,
      is_fee_paid: True,
      is_proceed_paid: True,
    }

  let tx = get_buy_test_tx(test_case)
  !marketplace.spend(
    mock_pub_key_address(0, None),
    100,
    Some(mock_datum()),
    redeemer,
    output_reference,
    tx,
  )
}

test fail_spend_marketplace_buy_without_fee_paid() {
  let output_reference = mock_utxo_ref(0, 1)
  let redeemer = Buy
  let test_case =
    BuyTestCase {
      is_only_one_input_from_script: True,
      is_fee_paid: False,
      is_proceed_paid: True,
    }

  let tx = get_buy_test_tx(test_case)
  !marketplace.spend(
    mock_pub_key_address(0, None),
    100,
    Some(mock_datum()),
    redeemer,
    output_reference,
    tx,
  )
}

test fail_spend_marketplace_buy_without_proceed_paid() {
  let output_reference = mock_utxo_ref(0, 1)
  let redeemer = Buy
  let test_case =
    BuyTestCase {
      is_only_one_input_from_script: True,
      is_fee_paid: True,
      is_proceed_paid: False,
    }

  let tx = get_buy_test_tx(test_case)
  !marketplace.spend(
    mock_pub_key_address(0, None),
    100,
    Some(mock_datum()),
    redeemer,
    output_reference,
    tx,
  )
}
