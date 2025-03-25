#[starknet::contract]
mod module {
    use starknet::EthAddress;
    use hdp_cairo::HDP;
    use hdp_cairo::evm::storage::{StorageImpl, StorageKey, StorageTrait};
    use core::keccak;

    // Define option types
    #[derive(Drop, Copy, Serde)]
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
    ) -> bool {
        let barrier_price = barrier_price.into();
        // Constants
        let samples_per_minute = 5_u32;
        let minute_samples = 4_u32;
        let blocks_to_skip = 50_u32; // Assuming approximately 10 minutes at 12 sec block time

        // Validate input addresses
        assert!(base_asset_oracle_address.into() != 0);
        assert!(quote_asset_oracle_address.into() != 0);
        
        // Get TWAP price ratio
        let twap_ratio = get_chainlink_twap_ratio(
            @hdp,
            base_asset_oracle_address,
            quote_asset_oracle_address,
            start_block,
            samples_per_minute,
            minute_samples,
            blocks_to_skip,
        );

        // Validate against barrier price based on option type
        let condition_met = match option_type {
            OptionType::Put => twap_ratio < barrier_price,
            OptionType::Call => twap_ratio > barrier_price,
        };

        // Assert that the condition is met
        assert!(condition_met);
        
        condition_met
    }

    fn get_chainlink_twap_ratio(
        hdp: @HDP,
        base_asset_oracle_address: EthAddress,
        quote_asset_oracle_address: EthAddress,
        start_block: felt252,
        samples_per_minute: u32,
        minute_samples: u32,
        blocks_to_skip: u32,
    ) -> u256 {
        let mut total_base_price: u256 = 0;
        let mut total_quote_price: u256 = 0;
        let mut total_samples: u32 = 0;

        // Loop through minute samples (separated by blocks_to_skip)
        let mut minute_counter: u32 = 0;
        while minute_counter < minute_samples {
            let skip_blocks: felt252 = (minute_counter * blocks_to_skip).into();
            let current_start_block = start_block + skip_blocks;
            
            // Take samples_per_minute consecutive blocks for each minute sample
            let mut block_counter: u32 = 0;
            while block_counter < samples_per_minute {
                let block_increment: felt252 = block_counter.into();
                let block_number = current_start_block + block_increment;
                
                // Get base asset price from Chainlink
                let base_price = get_chainlink_price(
                    hdp, 
                    base_asset_oracle_address, 
                    block_number
                );
                
                // Get quote asset price from Chainlink
                let quote_price = get_chainlink_price(
                    hdp, 
                    quote_asset_oracle_address, 
                    block_number
                );

                // Validate prices
                assert!(base_price != 0);
                assert!(quote_price != 0);
                
                // Add to totals
                total_base_price += base_price;
                total_quote_price += quote_price;
                total_samples += 1;
                
                block_counter += 1;

                break;
            };
            
            minute_counter += 1;
        };
        
        // Ensure we collected all expected samples
        let expected_samples = samples_per_minute * minute_samples;
        assert!(total_samples == expected_samples);
        
        // Calculate average prices
        let total_samples_u256: u256 = total_samples.into();
        let avg_base_price = total_base_price / total_samples_u256;
        let avg_quote_price = total_quote_price / total_samples_u256;
        
        // Ensure we have a non-zero denominator
        assert!(avg_quote_price != 0);
        
        // Calculate price ratio (base/quote)
        // Multiply by 1e18 for precision in division
        let scaling_factor = u256 { low: 1000000000000000000, high: 0 }; // 1e18
        let ratio = (avg_base_price * scaling_factor) / avg_quote_price;
        
        ratio
    }

    fn get_chainlink_price(
        hdp: @HDP, 
        oracle_address: EthAddress, 
        block_number: felt252
    ) -> u256 {
        // Constants
        // Use constant for Ethereum chain ID
        //let ethereum_chain_id = 11155111; // Sepolia Ethereum chain ID
        let ethereum_chain_id = 1; // Ethereum mainnet chain ID

        // 1. Get the round ID from the Chainlink oracle
        let round_storage_slot = 0x000000000000000000000000000000000000000000000000000000000000000b;
        let round_storage_key = StorageKey {
            chain_id: ethereum_chain_id,
            block_number: block_number,
            address: oracle_address.into(),
            storage_slot: round_storage_slot,
        };

        // Retrieve the raw storage value
        let raw_storage_value = hdp
            .evm
            .storage_get_slot(
                @round_storage_key
            );

        // Apply bit shift of 4 bytes (32 bits) to the retrieved storage value
        let shifted_value = raw_storage_value / 0x100000000;  // Right shift by 32 bits

        // Ensure we got a valid round ID
        assert!(shifted_value != 0);

        // Convert to round_id
        let round_id: u32 = shifted_value.try_into().unwrap();
        let round_id_u256: u256 = round_id.into();

        // 2. Calculate storage slot for price data using keccak
        // Create array with round_id and constant for keccak input
        let input = array![round_id_u256, 0x000000000000000000000000000000000000000000000000000000000000000c];
        
        // Compute keccak hash using big-endian format (Ethereum standard)
        let price_slot = keccak::keccak_u256s_be_inputs(input.span());

        // 3. Create a storage key for the price using the slot
        let price_storage_key = StorageKey {
            chain_id: ethereum_chain_id,
            block_number: block_number,
            address: oracle_address.into(),
            storage_slot: price_slot,
        };

        // 4. Retrieve price data
        let full_price_data = hdp
            .evm
            .storage_get_slot(
                @price_storage_key
            );

        // 5. Extract lowest 24 bytes (mask out the top 8 bytes)
        let mask = 0x0000000000000000ffffffffffffffffffffffffffffffffffffffffffffffff;
        let price_data_24_bytes = full_price_data & mask;

        // Ensure we got a valid price (non-zero)
        assert!(price_data_24_bytes != 0);
        
        price_data_24_bytes
    }
}