This project is meant to be a stablecoin where users can deposit WETH and WBTC in exchange for a token that will be pegged to the USD.


Deployment to a testnet or mainnet:
Setup environment variables
You'll want to set your SEPOLIA_RPC_URL and PRIVATE_KEY as environment variables. You can add them to a .env file, similar to what you see in .env.example.

PRIVATE_KEY: The private key of your account (like from metamask). NOTE: FOR DEVELOPMENT, PLEASE USE A KEY THAT DOESN'T HAVE ANY REAL FUNDS ASSOCIATED WITH IT.
You can learn how to export it here.
SEPOLIA_RPC_URL: This is url of the sepolia testnet node you're working with. You can get setup with one for free from Alchemy
Optionally, add your ETHERSCAN_API_KEY if you want to verify your contract on Etherscan.

Get testnet ETH
Head over to faucets.chain.link and get some testnet ETH. You should see the ETH show up in your metamask.

Deploy
make deploy ARGS="--network sepolia"

You can estimate how much gas things cost by running:

forge snapshot
And you'll see an output file called .gas-snapshot

About this project:
1. Relative Stability: Anchored/Pegged to USD
    1. Chainlink Pricefeed
2. stability machanism (minting): Algorithimic
    1. people can only mint the stablecoin with enough collateral (coded in)
3. Collateral type: exogenous (crypto)
    1. wETH
    2. wBTC