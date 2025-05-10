// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract MockFailedMintDSC is DecentralizedStableCoin {
    constructor() DecentralizedStableCoin() {}

    function mint(address _to, uint256 _amount) public override returns (bool) {
        return false;
    }
}
