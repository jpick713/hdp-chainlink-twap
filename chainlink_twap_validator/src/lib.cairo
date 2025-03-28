#[starknet::contract]
mod module {
    use starknet::EthAddress;
    use hdp_cairo::HDP;
    use hdp_cairo::evm::storage::{StorageImpl, StorageKey, StorageTrait};
    use core::keccak;
    use core::integer::u128_byte_reverse;

    // Define option types
    #[derive(Drop, Copy, Serde, Debug)]
    enum OptionType {
        Put,
        Call,
    }

    #[storage]
    struct Storage {}

    #[external(v0)]
    pub fn main(
        ref self: ContractState,
        hdp: HDP,
        base_asset_oracle_address: EthAddress,
        quote_asset_oracle_address: EthAddress,
        start_block: felt252,
        barrier_price: felt252,
        option_type: OptionType,
        quote_decimals: u8, // <-- New input for quote asset decimals
    ) -> bool {
        // Convert barrier_price to u256 for comparison with the calculated TWAP ratio.
        // IMPORTANT ASSUMPTION: barrier_price is provided already scaled by 10**quote_decimals.
        // Using unwrap() as felt252 should always fit into u256 unless it's negative (which is unlikely for a price).
        let barrier_price_u256: u256 = barrier_price.try_into().unwrap();
        println!("Debug - Received Barrier Price (scaled): {}", barrier_price_u256);

        // Constants for sampling strategy
        let samples_per_minute = 5_u32;
        let minute_samples = 4_u32;
        let blocks_to_skip = 50_u32; // ~10 minutes skip

        // Validate input addresses
        assert!(base_asset_oracle_address.into() != 0, "Base oracle address is zero");
        assert!(quote_asset_oracle_address.into() != 0, "Quote oracle address is zero");
        assert!(quote_decimals <= 38, "Quote decimals too large for safe scaling factor calculation"); // u256 can hold up to ~10^77

        // Get TWAP price ratio (scaled by 10**quote_decimals)
        let avg_ratio = get_chainlink_twap_ratio(
            @hdp,
            base_asset_oracle_address,
            quote_asset_oracle_address,
            start_block,
            samples_per_minute,
            minute_samples,
            blocks_to_skip,
            quote_decimals, // Pass decimals down
        );

        // Validate against barrier price based on option type
        let condition_met = match option_type {
            OptionType::Put => avg_ratio < barrier_price_u256,
            OptionType::Call => avg_ratio > barrier_price_u256,
        };

        // --- Start: Added Final Debug Print ---
        println!("--- Final Comparison ---");
        println!("Option Type: {:?}", option_type); // Print enum variant
        println!("Quote Decimals: {}", quote_decimals);
        println!("Calculated Avg Ratio (scaled): {}", avg_ratio);
        println!("Input Barrier Price (scaled): {}", barrier_price_u256);

        // Show the comparison explicitly
        match option_type {
            OptionType::Put => {
                println!("Check: (Avg Ratio Scaled < Barrier Scaled) -> ({} < {})",
                    avg_ratio,
                    barrier_price_u256
                );
            },
            OptionType::Call => {
                println!("Check: (Avg Ratio Scaled > Barrier Scaled) -> ({} > {})",
                    avg_ratio,
                    barrier_price_u256
                );
            },
        }

        println!("Condition Met Result: {}", condition_met);
        println!("------------------------");
        // --- End: Added Final Debug Print ---

        condition_met // Return the result
    }

    // Calculates the TWAP by averaging the ratio of base/quote price for each sample.
    // The ratio is scaled by 10^quote_decimals for precision.
    fn get_chainlink_twap_ratio(
        hdp: @HDP,
        base_asset_oracle_address: EthAddress,
        quote_asset_oracle_address: EthAddress,
        start_block: felt252,
        samples_per_minute: u32,
        minute_samples: u32,
        blocks_to_skip: u32,
        quote_decimals: u8, // <-- Receive quote asset decimals
    ) -> u256 {
        let mut total_ratio_sum: u256 = 0;
        let mut total_samples: u32 = 0;

        // Calculate scaling_factor = 10 ^ quote_decimals
        let mut scaling_factor: u256 = 1;
        let ten_u256: u256 = 10;
        let mut i: u8 = 0;
        while i < quote_decimals {
            scaling_factor = scaling_factor * ten_u256;
            i += 1;
        }
        println!("Debug - Calculated scaling_factor (10^{}): {}", quote_decimals, scaling_factor);

        let mut minute_counter: u32 = 0;
        println!("Starting TWAP calculation loop...");
        while minute_counter < minute_samples {
            let skip_blocks: felt252 = (minute_counter * blocks_to_skip).into();
            let current_start_block = start_block + skip_blocks;
            //println!("Debug - Processing minute sample {}, starting block: {}", minute_counter, current_start_block);

            let mut block_counter: u32 = 0;
            while block_counter < samples_per_minute {
                let block_increment: felt252 = block_counter.into();
                let block_number = current_start_block + block_increment;
                //println!("Debug -   Fetching prices for block: {}", block_number);

                let base_price = get_chainlink_price(hdp, base_asset_oracle_address, block_number);
                let quote_price = get_chainlink_price(hdp, quote_asset_oracle_address, block_number);

                assert!(base_price != 0, "Base price is zero");
                assert!(quote_price != 0, "Quote price is zero");
                println!("Debug -     Base Price: {}, Quote Price: {}", base_price, quote_price);


                // Calculate ratio: (base_price * scaling_factor) / quote_price
                let current_scaled_base = base_price * scaling_factor;
                let current_ratio = current_scaled_base / quote_price;
                println!("Debug -     Current Ratio (scaled): {}", current_ratio);
                total_ratio_sum += current_ratio;

                total_samples += 1;
                block_counter += 1;
            }; // End inner block_counter loop
            minute_counter += 1;
        }; // End outer minute_counter loop

        let expected_samples = samples_per_minute * minute_samples;
        //println!("Debug - TWAP Loop Finished. Total samples collected: {}", total_samples);
        assert!(total_samples == expected_samples, "Incorrect number of samples collected");

        let total_samples_u256: u256 = total_samples.into();
        assert!(total_samples_u256 != 0, "Total samples is zero");

        println!("Debug - Total Ratio Sum (scaled): {}", total_ratio_sum);
        let avg_ratio = total_ratio_sum / total_samples_u256;
        println!("Debug - Calculated Average Ratio (scaled): {}", avg_ratio);

        avg_ratio // Return the average ratio (scaled by 10^quote_decimals)
    }

    // Gets price from Chainlink via HDP
    fn get_chainlink_price(
        hdp: @HDP,
        oracle_address: EthAddress,
        block_number: felt252
    ) -> u256 {
        // Constants
        let ethereum_chain_id = 1; // Ethereum mainnet chain ID

        // 1. Get the round ID storage slot value (from slot 0xb)
        let round_storage_slot = 0x0b;
        let round_storage_key = StorageKey {
            chain_id: ethereum_chain_id,
            block_number: block_number,
            address: oracle_address.into(),
            storage_slot: round_storage_slot,
        };
        let raw_storage_value = hdp.evm.storage_get_slot(@round_storage_key);

        // Extract round ID (assuming right shift 48 bits, then mask lower 32 bits)
        let shifted_value = raw_storage_value / 0x1000000000000;
        let masked_value = shifted_value & 0xFFFFFFFF;
        assert!(masked_value != 0, "Extracted round ID is zero");
        let round_id: u32 = masked_value.try_into().unwrap(); // Safe due to mask
        let round_id_u256: u256 = round_id.into();

        // 2. Calculate storage slot for price data using keccak(roundId, mapping_slot)
        let mapping_base_slot = 0x0c; // Slot for 's_rounds' mapping
        let input = array![round_id_u256, mapping_base_slot.into()]; // Keccak inputs need to be u256
        let little_endian_hash_result: u256 = keccak::keccak_u256s_be_inputs(input.span());

        // Convert hash to Big-Endian u256 for storage slot lookup
        let reversed_low_part: u128 = u128_byte_reverse(little_endian_hash_result.low);
        let reversed_high_part: u128 = u128_byte_reverse(little_endian_hash_result.high);
        let big_endian_storage_slot_value: u256 = u256 { low: reversed_high_part, high: reversed_low_part };

        // 3. Create storage key for the price data
        let price_storage_key = StorageKey {
            chain_id: ethereum_chain_id,
            block_number: block_number,
            address: oracle_address.into(),
            storage_slot: big_endian_storage_slot_value,
        };

        // 4. Retrieve price data (packed)
        let full_price_data = hdp.evm.storage_get_slot(@price_storage_key);

        // 5. Extract the price (answer), assuming lower 192 bits (24 bytes)
        // IMPORTANT: This mask depends on the exact packing used by the Chainlink Aggregator version.
        let mask = 0x0000000000000000ffffffffffffffffffffffffffffffffffffffffffffffff;
        let price_data_extracted = full_price_data & mask;

        assert!(price_data_extracted != 0, "Extracted price is zero after masking");

        price_data_extracted
    }
}