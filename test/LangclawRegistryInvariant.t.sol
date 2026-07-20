// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LangclawRegistry} from "../src/LangclawRegistry.sol";

contract LangclawRegistryHandler is Test {
    LangclawRegistry internal immutable registry;

    uint256 public successfulWrites;
    uint256 public lastDecisionId;
    uint256 public lastAgentId;
    bytes32 public lastDecisionHash;
    address public lastRecorder;

    constructor(LangclawRegistry registry_) {
        registry = registry_;
    }

    function record(uint256 agentId, uint256 recorderSeed) public {
        address recorder = address(uint160(bound(recorderSeed, 1, type(uint160).max)));
        bytes32 decisionHash = keccak256(abi.encode(agentId, successfulWrites, recorder));

        vm.prank(recorder);
        uint256 decisionId = registry.recordAgentDecision(
            agentId, "invariant-run", decisionHash, "ipfs://invariant-evidence", "invariant-signal"
        );

        successfulWrites += 1;
        lastDecisionId = decisionId;
        lastAgentId = agentId;
        lastDecisionHash = decisionHash;
        lastRecorder = recorder;
    }
}

contract LangclawRegistryInvariantTest is Test {
    LangclawRegistry internal registry;
    LangclawRegistryHandler internal handler;

    function setUp() public {
        registry = new LangclawRegistry();
        handler = new LangclawRegistryHandler(registry);
        targetContract(address(handler));
    }

    function invariant_DecisionIdsMatchSuccessfulWrites() public view {
        assertEq(registry.nextDecisionId(), handler.successfulWrites());
    }

    function invariant_LastDecisionPreservesRecorderAndPayload() public view {
        if (handler.successfulWrites() == 0) {
            return;
        }

        LangclawRegistry.AgentDecision memory decision = registry.getDecision(handler.lastDecisionId());

        assertEq(decision.agentId, handler.lastAgentId());
        assertEq(decision.decisionHash, handler.lastDecisionHash());
        assertEq(decision.recorder, handler.lastRecorder());
        assertEq(keccak256(bytes(decision.runId)), keccak256(bytes("invariant-run")));
        assertEq(keccak256(bytes(decision.evidenceUri)), keccak256(bytes("ipfs://invariant-evidence")));
        assertEq(keccak256(bytes(decision.signalType)), keccak256(bytes("invariant-signal")));
    }
}
