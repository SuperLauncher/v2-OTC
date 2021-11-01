// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface ISuperDeedNFT {
    function mint(address to, uint weight) external returns (uint);
    function setTotalRaise(uint raised, uint entitledTokens) external;
}
