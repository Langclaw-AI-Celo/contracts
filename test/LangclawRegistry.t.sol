// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LangclawRegistry} from "../src/LangclawRegistry.sol";

contract LangclawRegistryTest is Test {
    LangclawRegistry internal registry;

    address internal recorder = makeAddr("recorder");

    event AgentDecisionRecorded(
        uint256 indexed decisionId,
        uint256 indexed agentId,
        address indexed recorder,
        bytes32 decisionHash,
        string runId,
        string evidenceUri,
        string signalType
    );

    function setUp() public {
        registry = new LangclawRegistry();
    }

    function test_RecordAgentDecision() public {
        bytes32 decisionHash = keccak256("mantle-alpha-run");

        vm.expectEmit(true, true, true, true, address(registry));
        emit AgentDecisionRecorded(
            0,
            8004,
            recorder,
            decisionHash,
            "run-1",
            "langclaw://evidence/run-1",
            "smart-money"
        );

        vm.prank(recorder);
        uint256 decisionId = registry.recordAgentDecision(
            8004,
            "run-1",
            decisionHash,
            "langclaw://evidence/run-1",
            "smart-money"
        );

        assertEq(decisionId, 0);
        assertEq(registry.nextDecisionId(), 1);

        LangclawRegistry.AgentDecision memory decision = registry.getDecision(decisionId);

        assertEq(decision.agentId, 8004);
        assertEq(decision.runId, "run-1");
        assertEq(decision.decisionHash, decisionHash);
        assertEq(decision.evidenceUri, "langclaw://evidence/run-1");
        assertEq(decision.signalType, "smart-money");
        assertEq(decision.recorder, recorder);
        assertGt(decision.createdAt, 0);
    }

    function test_RevertEmptyDecisionHash() public {
        vm.expectRevert(LangclawRegistry.EmptyDecisionHash.selector);

        registry.recordAgentDecision(
            8004,
            "run-1",
            bytes32(0),
            "langclaw://evidence/run-1",
            "smart-money"
        );
    }

    function test_RevertEmptyRunId() public {
        vm.expectRevert(LangclawRegistry.EmptyRunId.selector);

        registry.recordAgentDecision(
            8004,
            "",
            keccak256("mantle-alpha-run"),
            "langclaw://evidence/run-1",
            "smart-money"
        );
    }

    function test_RevertEmptyEvidenceUri() public {
        vm.expectRevert(LangclawRegistry.EmptyEvidenceUri.selector);

        registry.recordAgentDecision(
            8004,
            "run-1",
            keccak256("mantle-alpha-run"),
            "",
            "smart-money"
        );
    }

    function test_RevertEmptySignalType() public {
        vm.expectRevert(LangclawRegistry.EmptySignalType.selector);

        registry.recordAgentDecision(
            8004,
            "run-1",
            keccak256("mantle-alpha-run"),
            "langclaw://evidence/run-1",
            ""
        );
    }

    function test_RevertMissingDecision() public {
        vm.expectRevert(
            abi.encodeWithSelector(LangclawRegistry.DecisionNotFound.selector, 1)
        );

        registry.getDecision(1);
    }
}
