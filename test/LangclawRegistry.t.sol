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
        bytes32 decisionHash = keccak256("celo-alpha-run");

        vm.expectEmit(true, true, true, true, address(registry));
        emit AgentDecisionRecorded(0, 8004, recorder, decisionHash, "run-1", "langclaw://evidence/run-1", "smart-money");

        vm.prank(recorder);
        uint256 decisionId =
            registry.recordAgentDecision(8004, "run-1", decisionHash, "langclaw://evidence/run-1", "smart-money");

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

    function test_RecordAgentDecisionAcceptsErc8021TaggedCalldata() public {
        bytes32 decisionHash = keccak256("tagged-celo-decision");
        bytes memory payload = abi.encodeCall(
            registry.recordAgentDecision,
            (9109, "tagged-run", decisionHash, "langclaw://evidence/tagged-run", "attribution")
        );
        bytes memory suffix = hex"63656c6f5f316139383733383633366462110080218021802180218021802180218021";

        vm.prank(recorder);
        (bool success, bytes memory result) = address(registry).call(bytes.concat(payload, suffix));

        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), 0);
        assertEq(registry.nextDecisionId(), 1);

        LangclawRegistry.AgentDecision memory decision = registry.getDecision(0);
        assertEq(decision.agentId, 9109);
        assertEq(decision.runId, "tagged-run");
        assertEq(decision.decisionHash, decisionHash);
        assertEq(decision.recorder, recorder);
    }

    function test_RecordsExactDecisionTimestamp() public {
        uint256 recordedAt = 1_800_000_000;
        vm.warp(recordedAt);

        vm.prank(recorder);
        uint256 decisionId = registry.recordAgentDecision(
            8004, "run-timestamp", keccak256("timestamped-decision"), "langclaw://evidence/timestamp", "proof"
        );

        assertEq(registry.getDecision(decisionId).createdAt, recordedAt);
    }

    function testFuzz_RecordsNonEmptyDecisionPayloads(
        uint256 agentId,
        string memory runId,
        bytes32 decisionHash,
        string memory evidenceUri,
        string memory signalType
    ) public {
        vm.assume(decisionHash != bytes32(0));

        runId = string.concat("run-", runId);
        evidenceUri = string.concat("langclaw://evidence/", evidenceUri);
        signalType = string.concat("signal-", signalType);

        vm.prank(recorder);
        uint256 decisionId = registry.recordAgentDecision(agentId, runId, decisionHash, evidenceUri, signalType);
        LangclawRegistry.AgentDecision memory decision = registry.getDecision(decisionId);

        assertEq(decision.agentId, agentId);
        assertEq(decision.runId, runId);
        assertEq(decision.decisionHash, decisionHash);
        assertEq(decision.evidenceUri, evidenceUri);
        assertEq(decision.signalType, signalType);
        assertEq(decision.recorder, recorder);
    }

    function test_IsolatesConsecutiveRecorderData() public {
        address secondRecorder = makeAddr("second-recorder");

        vm.prank(recorder);
        uint256 firstId = registry.recordAgentDecision(
            8004, "run-first", keccak256("first-decision"), "langclaw://evidence/first", "smart-money"
        );

        vm.prank(secondRecorder);
        uint256 secondId = registry.recordAgentDecision(
            133, "run-second", keccak256("second-decision"), "langclaw://evidence/second", "liquidity"
        );

        LangclawRegistry.AgentDecision memory first = registry.getDecision(firstId);
        LangclawRegistry.AgentDecision memory second = registry.getDecision(secondId);

        assertEq(first.runId, "run-first");
        assertEq(first.recorder, recorder);
        assertEq(second.runId, "run-second");
        assertEq(second.recorder, secondRecorder);
        assertEq(registry.nextDecisionId(), 2);
    }

    function test_RevertEmptyDecisionHash() public {
        vm.expectRevert(LangclawRegistry.EmptyDecisionHash.selector);

        registry.recordAgentDecision(8004, "run-1", bytes32(0), "langclaw://evidence/run-1", "smart-money");
    }

    function test_RevertEmptyRunId() public {
        vm.expectRevert(LangclawRegistry.EmptyRunId.selector);

        registry.recordAgentDecision(8004, "", keccak256("celo-alpha-run"), "langclaw://evidence/run-1", "smart-money");
    }

    function test_RevertEmptyEvidenceUri() public {
        vm.expectRevert(LangclawRegistry.EmptyEvidenceUri.selector);

        registry.recordAgentDecision(8004, "run-1", keccak256("celo-alpha-run"), "", "smart-money");
    }

    function test_RevertEmptySignalType() public {
        vm.expectRevert(LangclawRegistry.EmptySignalType.selector);

        registry.recordAgentDecision(8004, "run-1", keccak256("celo-alpha-run"), "langclaw://evidence/run-1", "");
    }

    function test_WhitespaceValidationPreservesMeaningfulDecisionMetadata() public {
        string memory blank = " \t\n\x0b\x0c\r";
        bytes32 decisionHash = keccak256("whitespace-only-decision");

        vm.expectRevert(LangclawRegistry.EmptyRunId.selector);
        registry.recordAgentDecision(8004, blank, decisionHash, "langclaw://evidence/run-1", "smart-money");

        vm.expectRevert(LangclawRegistry.EmptyEvidenceUri.selector);
        registry.recordAgentDecision(8004, "run-1", decisionHash, blank, "smart-money");

        vm.expectRevert(LangclawRegistry.EmptySignalType.selector);
        registry.recordAgentDecision(8004, "run-1", decisionHash, "langclaw://evidence/run-1", blank);

        assertEq(registry.nextDecisionId(), 0);

        string memory meaningful = " \tvalue\r\n";
        uint256 decisionId = registry.recordAgentDecision(8004, meaningful, decisionHash, meaningful, meaningful);
        LangclawRegistry.AgentDecision memory decision = registry.getDecision(decisionId);

        assertEq(decision.runId, meaningful);
        assertEq(decision.evidenceUri, meaningful);
        assertEq(decision.signalType, meaningful);
        assertEq(registry.nextDecisionId(), 1);
    }

    function test_RevertMissingDecision() public {
        vm.expectRevert(abi.encodeWithSelector(LangclawRegistry.DecisionNotFound.selector, 1));

        registry.getDecision(1);
    }

    function test_RevertAtMissingDecisionBoundary() public {
        uint256 existingId = registry.recordAgentDecision(
            8004, "run-existing", keccak256("existing"), "langclaw://evidence/existing", "proof"
        );
        uint256 missingId = registry.nextDecisionId();

        assertEq(registry.getDecision(existingId).runId, "run-existing");
        vm.expectRevert(abi.encodeWithSelector(LangclawRegistry.DecisionNotFound.selector, missingId));
        registry.getDecision(missingId);
    }
}
