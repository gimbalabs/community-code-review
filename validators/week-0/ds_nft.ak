// 🫀 mint and burn ds_nft 

// originally forked from the plutus-nft contract by @https://github.com/HinsonSIDAN Apache 2.0 license
// https://github.com/MeshJS/mesh/blob/main/packages/mesh-contract/src/plutus-nft/aiken-workspace/validators/plutus_nft.ak

use cardano/assets.{PolicyId, add, from_asset}
use cardano/transaction.{InlineDatum, Input, Transaction}
use cocktail.{
  check_policy_only_burn, convert_int_to_bytes, inputs_with_policy,
  only_minted_token,
}
use mocktail.{
  complete, mint, mock_policy_id, mock_script_address, mock_tx_hash, mocktail_tx,
  tx_in, tx_in_inline_datum,
}
use oracle.{DatumTestCase, OracleDatum, datum_with_updates}

pub type MintPolarity {
  RMint
  RBurn
}

validator ds_nft(oracle_nft: PolicyId) {
  mint(redeemer: MintPolarity, policy_id: PolicyId, tx: Transaction) {
    when redeemer is {
      RMint -> {
        // find exactly 1 input with oracle nft
        expect [oracle_input] = inputs_with_policy(tx.inputs, oracle_nft)
        // with inline datum of some type
        expect InlineDatum(input_datum) = oracle_input.output.datum
        // specifically type OracleDatum with a count field
        expect OracleDatum { count, .. }: OracleDatum = input_datum
      // only one token is minted using count as asset name
        only_minted_token(tx.mint, policy_id, convert_int_to_bytes(count), 1)
      }
    // all minting values are negative 
      RBurn -> check_policy_only_burn(tx.mint, policy_id)
    }
  }

  else(_) {
    fail
  }
}

//  tests

const redeemer_standard = RMint

const redeemer_burn_standard = RBurn

const policy_id_standard = mock_policy_id(0)

const oracle_utxo_input_standard =
  from_asset(mock_policy_id(0), "", 1) |> add("", "", 2_000_000)

const datum_standard =
  datum_with_updates(
    DatumTestCase {
      count: None,
      treasury_address: None,
      pot_address: None,
      fee_address: None,
      winner: None,
      treasury_price: None,
      pot_price: None,
      fee_price: None,
      slot_start: None,
      slot_increase: None,
      divisor: None,
    },
  )

test success_mint_ds() {
  let tx =
    mocktail_tx()
      |> tx_in(
          True,
          mock_tx_hash(0),
          0,
          oracle_utxo_input_standard,
          mock_script_address(0, None),
        )
      |> tx_in_inline_datum(True, datum_standard)
      |> mint(True, 1, policy_id_standard, "0")
      // asset name is same as count
      |> complete()
  ds_nft.mint(mock_policy_id(0), redeemer_standard, policy_id_standard, tx)
}

test fail_mint_ds_with_incorrect_name() {
  let tx =
    mocktail_tx()
      |> tx_in(
          True,
          mock_tx_hash(0),
          0,
          oracle_utxo_input_standard,
          mock_script_address(0, None),
        )
      |> tx_in_inline_datum(True, datum_standard)
      |> mint(True, 1, policy_id_standard, "1")
      // asset name is different from count
      |> complete()
  !ds_nft.mint(mock_policy_id(0), redeemer_standard, policy_id_standard, tx)
}

test fail_mint_ds_with_multiple_mint() {
  let policy_id_different = mock_policy_id(14)
  let tx =
    mocktail_tx()
      |> tx_in(
          True,
          mock_tx_hash(0),
          0,
          oracle_utxo_input_standard,
          mock_script_address(0, None),
        )
      |> tx_in_inline_datum(True, datum_standard)
      |> mint(True, 1, policy_id_standard, "0")
      |> mint(True, 1, policy_id_different, "0")
      // cannot have multiple mints with any policy
      |> complete()
  !ds_nft.mint(mock_policy_id(0), redeemer_standard, policy_id_standard, tx)
}

test success_burn_ds() {
  let tx =
    mocktail_tx()
      |> mint(True, -1, policy_id_standard, "")
      |> complete()
  ds_nft.mint(mock_policy_id(0), redeemer_burn_standard, policy_id_standard, tx)
}

test success_burn_ds_with_other_policy_also_burning_edge_case() {
  let tx =
    mocktail_tx()
      |> mint(True, -1, policy_id_standard, "")
      |> mint(True, -1, mock_policy_id(1), "")
      // edge case we can burn other policies too
      |> complete()
  ds_nft.mint(mock_policy_id(0), redeemer_burn_standard, policy_id_standard, tx)
}

test fail_burn_ds_with_mint() {
  let tx =
    mocktail_tx()
      |> mint(True, 1, policy_id_standard, "")
      |> complete()
  !ds_nft.mint(
    mock_policy_id(0),
    redeemer_burn_standard,
    policy_id_standard,
    tx,
  )
}

test fail_burn_ds_with_mint_and_burn() {
  let tx =
    mocktail_tx()
      |> mint(True, -1, policy_id_standard, "")
      // cannot burn and mint at the same time
      |> mint(True, 1, policy_id_standard, "1")
      |> complete()
  !ds_nft.mint(
    mock_policy_id(0),
    redeemer_burn_standard,
    policy_id_standard,
    tx,
  )
}

test success_vodka_only_minted_token_test() {
  let mint = from_asset(policy_id_standard, "", 1)
  only_minted_token(mint, policy_id_standard, "", 1)
}

test fail_vodka_only_minted_token_test() {
  let mint = from_asset(policy_id_standard, "", 2)
  // try to mint 2 tokens
  !only_minted_token(mint, policy_id_standard, "", 1)
}
