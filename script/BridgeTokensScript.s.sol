// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    function run(
        address receiverAddress,
        address rebaseToken,
        uint256 rebaseTokenAmount,
        address ccipRouterAddress,
        uint64 remoteChainSelector,
        address linkAddress,
        address routerAddress
    ) public {
        vm.startBroadcast();

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: rebaseToken, amount: rebaseTokenAmount});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 0, allowOutOfOrderExecution: false}))
        });

        uint256 bridgeFee = IRouterClient(routerAddress).getFee(remoteChainSelector, message);
        IERC20(linkAddress).approve(routerAddress, bridgeFee);
        IERC20(address(rebaseToken)).approve(routerAddress, rebaseTokenAmount);
        IRouterClient(ccipRouterAddress).ccipSend(remoteChainSelector, message);

        vm.stopBroadcast();
    }
}
