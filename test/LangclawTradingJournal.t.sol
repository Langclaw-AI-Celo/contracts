// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LangclawTradingJournal} from "../src/LangclawTradingJournal.sol";

contract LangclawTradingJournalTest is Test {
    LangclawTradingJournal internal journal;

    address internal recorder = makeAddr("recorder");

    event StrategyRecordRecorded(
        uint256 indexed recordId,
        uint256 indexed agentId,
        address indexed recorder,
        bytes32 decisionHash,
        bytes32 resultHash,
        string runId,
        string strategyId,
        string market,
        string evidenceUri,
        string action,
        int256 pnlBps,
        string status
    );

    function setUp() public {
        journal = new LangclawTradingJournal();
    }

    function test_RecordValidStrategyRun() public {
        bytes32 decisionHash = keccak256("strategy-decision");
        bytes32 resultHash = keccak256("strategy-result");

        vm.expectEmit(true, true, true, true, address(journal));
        emit StrategyRecordRecorded(
            0,
            133,
            recorder,
            decisionHash,
            resultHash,
            "paper-1",
            "celo-liquidity-momentum-v1",
            "celo:0x1111111111111111111111111111111111111111",
            "langclaw://strategy/paper-1",
            "buy",
            120,
            "paper-opened"
        );

        vm.prank(recorder);
        uint256 recordId = journal.recordStrategyRun(
            133,
            "paper-1",
            "celo-liquidity-momentum-v1",
            "celo:0x1111111111111111111111111111111111111111",
            decisionHash,
            resultHash,
            "langclaw://strategy/paper-1",
            "buy",
            120,
            "paper-opened"
        );

        assertEq(recordId, 0);
        assertEq(journal.nextRecordId(), 1);

        LangclawTradingJournal.StrategyRecord memory record = journal.getRecord(recordId);

        assertEq(record.agentId, 133);
        assertEq(record.runId, "paper-1");
        assertEq(record.strategyId, "celo-liquidity-momentum-v1");
        assertEq(record.market, "celo:0x1111111111111111111111111111111111111111");
        assertEq(record.decisionHash, decisionHash);
        assertEq(record.resultHash, resultHash);
        assertEq(record.evidenceUri, "langclaw://strategy/paper-1");
        assertEq(record.action, "buy");
        assertEq(record.pnlBps, 120);
        assertEq(record.status, "paper-opened");
        assertEq(record.recorder, recorder);
        assertGt(record.createdAt, 0);
    }

    function test_RecordStrategyRunAcceptsErc8021TaggedCalldata() public {
        bytes32 decisionHash = keccak256("tagged-strategy-decision");
        bytes32 resultHash = keccak256("tagged-strategy-result");
        bytes memory payload = abi.encodeCall(
            journal.recordStrategyRun,
            (
                9109,
                "tagged-strategy-run",
                "celo-attribution-v1",
                "celo:usdt",
                decisionHash,
                resultHash,
                "langclaw://strategy/tagged-run",
                "hold",
                25,
                "backtested"
            )
        );
        bytes memory suffix = hex"63656c6f5f316139383733383633366462110080218021802180218021802180218021";

        vm.prank(recorder);
        (bool success, bytes memory result) = address(journal).call(bytes.concat(payload, suffix));

        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), 0);
        assertEq(journal.nextRecordId(), 1);

        LangclawTradingJournal.StrategyRecord memory record = journal.getRecord(0);
        assertEq(record.agentId, 9109);
        assertEq(record.runId, "tagged-strategy-run");
        assertEq(record.decisionHash, decisionHash);
        assertEq(record.resultHash, resultHash);
        assertEq(record.recorder, recorder);
    }

    function test_RecordsExactStrategyTimestamp() public {
        uint256 recordedAt = 1_800_000_100;
        vm.warp(recordedAt);

        vm.prank(recorder);
        uint256 recordId = journal.recordStrategyRun(
            133,
            "timestamped-run",
            "celo-liquidity-momentum-v1",
            "celo:pair",
            keccak256("timestamped-decision"),
            keccak256("timestamped-result"),
            "langclaw://strategy/timestamped-run",
            "hold",
            0,
            "backtested"
        );

        assertEq(journal.getRecord(recordId).createdAt, recordedAt);
    }

    function testFuzz_RecordsSignedPnlAndPayloads(
        int256 pnlBps,
        uint256 agentId,
        string memory runId,
        bytes32 decisionHash,
        bytes32 resultHash,
        string memory status
    ) public {
        vm.assume(bytes(runId).length > 0);
        vm.assume(decisionHash != bytes32(0));
        vm.assume(resultHash != bytes32(0));
        vm.assume(bytes(status).length > 0);

        vm.prank(recorder);
        uint256 recordId = journal.recordStrategyRun(
            agentId,
            runId,
            "fuzz-strategy",
            "celo:fuzz-market",
            decisionHash,
            resultHash,
            "langclaw://strategy/fuzz",
            "hold",
            pnlBps,
            status
        );
        LangclawTradingJournal.StrategyRecord memory record = journal.getRecord(recordId);

        assertEq(record.agentId, agentId);
        assertEq(record.runId, runId);
        assertEq(record.decisionHash, decisionHash);
        assertEq(record.resultHash, resultHash);
        assertEq(record.pnlBps, pnlBps);
        assertEq(record.status, status);
        assertEq(record.recorder, recorder);
    }

    function test_IsolatesConsecutiveRecorderData() public {
        address secondRecorder = makeAddr("second-recorder");

        vm.prank(recorder);
        uint256 firstId = journal.recordStrategyRun(
            133,
            "run-first",
            "strategy-first",
            "celo:first",
            keccak256("decision-first"),
            keccak256("result-first"),
            "langclaw://strategy/first",
            "buy",
            -25,
            "paper-opened"
        );

        vm.prank(secondRecorder);
        uint256 secondId = journal.recordStrategyRun(
            8004,
            "run-second",
            "strategy-second",
            "celo:second",
            keccak256("decision-second"),
            keccak256("result-second"),
            "langclaw://strategy/second",
            "sell",
            75,
            "paper-closed"
        );

        LangclawTradingJournal.StrategyRecord memory first = journal.getRecord(firstId);
        LangclawTradingJournal.StrategyRecord memory second = journal.getRecord(secondId);

        assertEq(first.strategyId, "strategy-first");
        assertEq(first.recorder, recorder);
        assertEq(second.strategyId, "strategy-second");
        assertEq(second.recorder, secondRecorder);
        assertEq(journal.nextRecordId(), 2);
    }

    function test_RevertEmptyRunId() public {
        vm.expectRevert(LangclawTradingJournal.EmptyRunId.selector);

        journal.recordStrategyRun(
            133,
            "",
            "celo-liquidity-momentum-v1",
            "celo:pair",
            keccak256("strategy-decision"),
            keccak256("strategy-result"),
            "langclaw://strategy/run",
            "buy",
            0,
            "backtested"
        );
    }

    function test_RevertEmptyStrategyId() public {
        vm.expectRevert(LangclawTradingJournal.EmptyStrategyId.selector);

        journal.recordStrategyRun(
            133,
            "run-1",
            "",
            "celo:pair",
            keccak256("strategy-decision"),
            keccak256("strategy-result"),
            "langclaw://strategy/run",
            "buy",
            0,
            "backtested"
        );
    }

    function test_RevertEmptyMarket() public {
        vm.expectRevert(LangclawTradingJournal.EmptyMarket.selector);

        journal.recordStrategyRun(
            133,
            "run-1",
            "celo-liquidity-momentum-v1",
            "",
            keccak256("strategy-decision"),
            keccak256("strategy-result"),
            "langclaw://strategy/run",
            "buy",
            0,
            "backtested"
        );
    }

    function test_RevertEmptyDecisionHash() public {
        vm.expectRevert(LangclawTradingJournal.EmptyDecisionHash.selector);

        journal.recordStrategyRun(
            133,
            "run-1",
            "celo-liquidity-momentum-v1",
            "celo:pair",
            bytes32(0),
            keccak256("strategy-result"),
            "langclaw://strategy/run",
            "buy",
            0,
            "backtested"
        );
    }

    function test_RevertEmptyResultHash() public {
        vm.expectRevert(LangclawTradingJournal.EmptyResultHash.selector);

        journal.recordStrategyRun(
            133,
            "run-1",
            "celo-liquidity-momentum-v1",
            "celo:pair",
            keccak256("strategy-decision"),
            bytes32(0),
            "langclaw://strategy/run",
            "buy",
            0,
            "backtested"
        );
    }

    function test_RevertEmptyEvidenceUri() public {
        vm.expectRevert(LangclawTradingJournal.EmptyEvidenceUri.selector);

        journal.recordStrategyRun(
            133,
            "run-1",
            "celo-liquidity-momentum-v1",
            "celo:pair",
            keccak256("strategy-decision"),
            keccak256("strategy-result"),
            "",
            "buy",
            0,
            "backtested"
        );
    }

    function test_RevertEmptyAction() public {
        vm.expectRevert(LangclawTradingJournal.EmptyAction.selector);

        journal.recordStrategyRun(
            133,
            "run-1",
            "celo-liquidity-momentum-v1",
            "celo:pair",
            keccak256("strategy-decision"),
            keccak256("strategy-result"),
            "langclaw://strategy/run",
            "",
            0,
            "backtested"
        );
    }

    function test_RevertEmptyStatus() public {
        vm.expectRevert(LangclawTradingJournal.EmptyStatus.selector);

        journal.recordStrategyRun(
            133,
            "run-1",
            "celo-liquidity-momentum-v1",
            "celo:pair",
            keccak256("strategy-decision"),
            keccak256("strategy-result"),
            "langclaw://strategy/run",
            "buy",
            0,
            ""
        );
    }

    function test_AllowsNegativeAndPositivePnlBps() public {
        uint256 lossId = journal.recordStrategyRun(
            133,
            "loss",
            "celo-liquidity-momentum-v1",
            "celo:pair",
            keccak256("loss-decision"),
            keccak256("loss-result"),
            "langclaw://strategy/loss",
            "exit",
            -550,
            "paper-closed"
        );
        uint256 winId = journal.recordStrategyRun(
            133,
            "win",
            "celo-liquidity-momentum-v1",
            "celo:pair",
            keccak256("win-decision"),
            keccak256("win-result"),
            "langclaw://strategy/win",
            "exit",
            1000,
            "paper-closed"
        );

        assertEq(journal.getRecord(lossId).pnlBps, -550);
        assertEq(journal.getRecord(winId).pnlBps, 1000);
    }

    function test_IncrementsRecordId() public {
        journal.recordStrategyRun(
            133,
            "run-1",
            "celo-liquidity-momentum-v1",
            "celo:pair",
            keccak256("decision-1"),
            keccak256("result-1"),
            "langclaw://strategy/run-1",
            "hold",
            0,
            "backtested"
        );
        uint256 second = journal.recordStrategyRun(
            133,
            "run-2",
            "celo-liquidity-momentum-v1",
            "celo:pair",
            keccak256("decision-2"),
            keccak256("result-2"),
            "langclaw://strategy/run-2",
            "buy",
            0,
            "paper-opened"
        );

        assertEq(second, 1);
        assertEq(journal.nextRecordId(), 2);
    }

    function test_RevertMissingRecord() public {
        vm.expectRevert(abi.encodeWithSelector(LangclawTradingJournal.RecordNotFound.selector, 1));

        journal.getRecord(1);
    }
}
