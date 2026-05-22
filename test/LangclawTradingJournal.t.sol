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
            94,
            recorder,
            decisionHash,
            resultHash,
            "paper-1",
            "mantle-liquidity-momentum-v1",
            "mantle:0x1111111111111111111111111111111111111111",
            "langclaw://strategy/paper-1",
            "buy",
            120,
            "paper-opened"
        );

        vm.prank(recorder);
        uint256 recordId = journal.recordStrategyRun(
            94,
            "paper-1",
            "mantle-liquidity-momentum-v1",
            "mantle:0x1111111111111111111111111111111111111111",
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

        assertEq(record.agentId, 94);
        assertEq(record.runId, "paper-1");
        assertEq(record.strategyId, "mantle-liquidity-momentum-v1");
        assertEq(record.market, "mantle:0x1111111111111111111111111111111111111111");
        assertEq(record.decisionHash, decisionHash);
        assertEq(record.resultHash, resultHash);
        assertEq(record.evidenceUri, "langclaw://strategy/paper-1");
        assertEq(record.action, "buy");
        assertEq(record.pnlBps, 120);
        assertEq(record.status, "paper-opened");
        assertEq(record.recorder, recorder);
        assertGt(record.createdAt, 0);
    }

    function test_RevertEmptyRunId() public {
        vm.expectRevert(LangclawTradingJournal.EmptyRunId.selector);

        journal.recordStrategyRun(
            94,
            "",
            "mantle-liquidity-momentum-v1",
            "mantle:pair",
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
            94,
            "run-1",
            "",
            "mantle:pair",
            keccak256("strategy-decision"),
            keccak256("strategy-result"),
            "langclaw://strategy/run",
            "buy",
            0,
            "backtested"
        );
    }

    function test_RevertEmptyEvidenceUri() public {
        vm.expectRevert(LangclawTradingJournal.EmptyEvidenceUri.selector);

        journal.recordStrategyRun(
            94,
            "run-1",
            "mantle-liquidity-momentum-v1",
            "mantle:pair",
            keccak256("strategy-decision"),
            keccak256("strategy-result"),
            "",
            "buy",
            0,
            "backtested"
        );
    }

    function test_RevertEmptyStatus() public {
        vm.expectRevert(LangclawTradingJournal.EmptyStatus.selector);

        journal.recordStrategyRun(
            94,
            "run-1",
            "mantle-liquidity-momentum-v1",
            "mantle:pair",
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
            94,
            "loss",
            "mantle-liquidity-momentum-v1",
            "mantle:pair",
            keccak256("loss-decision"),
            keccak256("loss-result"),
            "langclaw://strategy/loss",
            "exit",
            -550,
            "paper-closed"
        );
        uint256 winId = journal.recordStrategyRun(
            94,
            "win",
            "mantle-liquidity-momentum-v1",
            "mantle:pair",
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
            94,
            "run-1",
            "mantle-liquidity-momentum-v1",
            "mantle:pair",
            keccak256("decision-1"),
            keccak256("result-1"),
            "langclaw://strategy/run-1",
            "hold",
            0,
            "backtested"
        );
        uint256 second = journal.recordStrategyRun(
            94,
            "run-2",
            "mantle-liquidity-momentum-v1",
            "mantle:pair",
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
}
