

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {MagicETH} from "src/ghost/magic/MagicETH.sol";

import {HodlMyBeerLending} from "src/ghost/hodlmybeer/HodlMyBeerLending.sol";

import {SpookyOracle} from "src/ghost/spooky/SpookyOracle.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {

        // TODO: deploy LTV also

        address proxyOwner = vm.envAddress("PROXY_OWNER");
        address magicETHOwner = vm.envAddress("MAGIC_ETH_OWNER");
        address oracleOwner = vm.envAddress("ORACLE_OWNER");
        address weth = vm.envAddress("WETH");

        console.log("proxyOwner: ", proxyOwner);
        console.log("magicETHOwner: ", magicETHOwner);
        console.log("oracleOwner: ", oracleOwner);
        console.log("weth: ", weth);

        vm.startBroadcast(); // Start broadcasting transactions

        address magicETHProxy = Upgrades.deployTransparentProxy(
            "MagicETH.sol",
            proxyOwner,
            abi.encodeCall(MagicETH.initialize, (magicETHOwner))
        );

        // ------------------------------------------------

        address spookyOracleProxy = Upgrades.deployTransparentProxy(
            "SpookyOracle.sol",
            proxyOwner,
            abi.encodeCall(SpookyOracle.initialize, oracleOwner)
        );

        // ------------------------------------------------

        // TODO: add link to WETH

        address hodlMyBeerLendingProxy = Upgrades.deployTransparentProxy(
            "HodlMyBeerLending.sol",
            address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
            abi.encodeCall(HodlMyBeerLending.initialize, (weth, address(magicETHProxy), address(spookyOracleProxy)))
        );

        // ------------------------------------------------

        console.log("proxyMagicETH at:         ", magicETHProxy);
        console.log("hodlMyBeerLendingProxy at:", hodlMyBeerLendingProxy);
        console.log("spookyOracleProxy at:     ", spookyOracleProxy);

        vm.stopBroadcast();
    }
}