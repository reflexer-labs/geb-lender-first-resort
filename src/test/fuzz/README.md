# Security Tests

The contracts in this folder are the fuzz scripts for the GEB repository.

To run the fuzzer, set up Echidna (https://github.com/crytic/echidna) on your machine.

Then run
```
echidna-test src/test/fuzz/<name of file>.sol --contract <Name of contract> --config src/test/fuzz/echidna.yaml
```

Configs are in this folder (echidna.yaml).

The fuzzing contract (Fuzz) will setup the contracts, and call Join, requestExit, exit and getRewards from various addresses. Helper functions will test main state changes for the one call, and invariants are tested for every call performed ("echidna_...")

# Staking pool with off chain rewards

The system is randomly thrown under/abovewater, to allow for auctions to start and all execution paths to be reached.

- Token flows on join, exit
- Main state changes on requestExit, auctionAncestorTokens, join, exit

Invariants
- Descendant supply
- Auctions started / funds transferred

## Result

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb-lender-first-resort/src/test/fuzz/GebLenderFirstResortFuzz.sol:Fuzz
echidna_auction_funds: passed! 🎉
echidna_ancestor_supply: passed! 🎉
echidna_descendant_supply: passed! 🎉
assertion in fuzz_under_above_water: passed! 🎉
assertion in test_echidna: passed! 🎉
assertion in doExit: passed! 🎉
assertion in doAuctionAncestorTokens: passed! 🎉
assertion in doRequestExit: passed! 🎉
assertion in doJoin: passed! 🎉

Seed: -5071447049419875706

```


# Staking pool with on chain rewards

## Tests

The system is randomly thrown under/abovewater, to allow for auctions to start and all execution paths to be reached.

- Token flows on join, exit
- Main state changes on requestExit, auctionAncestorTokens, join, exit
- Rewards calculation / token flows

Invariants
- Descendant supply
- Rewards granted within bounds
- Auctions started / funds transferred

## Result

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb-lender-first-resort/src/test/fuzz/GebLenderFirstResortRewardsFuzz.sol:Fuzz
echidna_rewards_given: passed! 🎉
echidna_auction_funds: passed! 🎉
echidna_ancestor_supply: passed! 🎉
assertion in doGetRewards: passed! 🎉
assertion in fuzz_under_above_water: passed! 🎉
assertion in doExit: passed! 🎉
assertion in doAuctionAncestorTokens: passed! 🎉
assertion in failed: passed! 🎉
assertion in doRequestExit: passed! 🎉
assertion in doJoin: passed! 🎉

Seed: -7956419779194474204
```