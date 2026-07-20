// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LangclawTradingJournal} from "../src/LangclawTradingJournal.sol";

contract LangclawTradingJournalHandler is Test {
    LangclawTradingJournal internal immutable journal;

    uint256 public successfulWrites;
    uint256 public lastRecordId;
    uint256 public lastAgentId;
    int256 public lastPnlBps;
    bytes32 public lastDecisionHash;
    bytes32 public lastResultHash;
    address public lastRecorder;

    constructor(LangclawTradingJournal journal_) {
        journal = journal_;
    }

    function record(uint256 agentId, int256 pnlBps, uint256 recorderSeed) public {
        address recorder = address(uint160(bound(recorderSeed, 1, type(uint160).max)));
        bytes32 decisionHash = keccak256(abi.encode("decision", agentId, successfulWrites, recorder));
        bytes32 resultHash = keccak256(abi.encode("result", agentId, successfulWrites, pnlBps));

        vm.prank(recorder);
        uint256 recordId = journal.recordStrategyRun(
            agentId,
            "invariant-run",
            "invariant-strategy",
            "CELO/USDT",
            decisionHash,
            resultHash,
            "ipfs://invariant-result",
            "hold",
            pnlBps,
            "complete"
        );

        successfulWrites += 1;
        lastRecordId = recordId;
        lastAgentId = agentId;
        lastPnlBps = pnlBps;
        lastDecisionHash = decisionHash;
        lastResultHash = resultHash;
        lastRecorder = recorder;
    }
}

contract LangclawTradingJournalInvariantTest is Test {
    LangclawTradingJournal internal journal;
    LangclawTradingJournalHandler internal handler;

    function setUp() public {
        journal = new LangclawTradingJournal();
        handler = new LangclawTradingJournalHandler(journal);
        targetContract(address(handler));
    }

    function invariant_RecordIdsMatchSuccessfulWrites() public view {
        assertEq(journal.nextRecordId(), handler.successfulWrites());
    }

    function invariant_LastRecordPreservesRecorderAndPayload() public view {
        if (handler.successfulWrites() == 0) {
            return;
        }

        LangclawTradingJournal.StrategyRecord memory record = journal.getRecord(handler.lastRecordId());

        assertEq(record.agentId, handler.lastAgentId());
        assertEq(record.pnlBps, handler.lastPnlBps());
        assertEq(record.decisionHash, handler.lastDecisionHash());
        assertEq(record.resultHash, handler.lastResultHash());
        assertEq(record.recorder, handler.lastRecorder());
        assertEq(keccak256(bytes(record.runId)), keccak256(bytes("invariant-run")));
        assertEq(keccak256(bytes(record.strategyId)), keccak256(bytes("invariant-strategy")));
        assertEq(keccak256(bytes(record.market)), keccak256(bytes("CELO/USDT")));
    }
}
