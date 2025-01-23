# Cross chain rebase token
1. A protocol that allows users to deposit into a vault and in return receive rebase tokens that represent their underlying balance - that will accrue interest
2. Rebase token -> balanceOf function is dynamic to show the changing balance with time
    - Balance increases linearly with time
    - mint tokens to our users every time they perform an action (minting, burning, transferring, or ... bridging)
3. Interest rate 
    - Individually set interest rate for each user based on some global interest rate of the protocol at the time the user deposits into the vault
    - This global interest rate can only decrease to incentivise/reward early adopters
    - Increase token adoption!