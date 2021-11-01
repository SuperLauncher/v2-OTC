// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IEmergency {
   function daoMultiSigEmergencyWithdraw(address to, address tokenAddress, uint amount) external;
}
