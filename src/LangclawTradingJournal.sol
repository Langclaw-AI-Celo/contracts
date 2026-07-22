// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LangclawProofValidation} from "./LangclawProofValidation.sol";

contract LangclawTradingJournal {
    using LangclawProofValidation for bytes32;
    using LangclawProofValidation for string;

    struct StrategyRecord {
        uint256 agentId;
        string runId;
        string strategyId;
        string market;
        bytes32 decisionHash;
        bytes32 resultHash;
        string evidenceUri;
        string action;
        int256 pnlBps;
        string status;
        address recorder;
        uint256 createdAt;
    }

    uint256 public nextRecordId;

    mapping(uint256 => StrategyRecord) private records;

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

    error EmptyRunId();
    error EmptyStrategyId();
    error EmptyMarket();
    error EmptyDecisionHash();
    error EmptyResultHash();
    error EmptyEvidenceUri();
    error EmptyAction();
    error EmptyStatus();
    error RecordNotFound(uint256 recordId);

    function recordStrategyRun(
        uint256 agentId,
        string calldata runId,
        string calldata strategyId,
        string calldata market,
        bytes32 decisionHash,
        bytes32 resultHash,
        string calldata evidenceUri,
        string calldata action,
        int256 pnlBps,
        string calldata status
    ) external returns (uint256 recordId) {
        if (runId.isBlank()) {
            revert EmptyRunId();
        }
        if (strategyId.isBlank()) {
            revert EmptyStrategyId();
        }
        if (market.isBlank()) {
            revert EmptyMarket();
        }
        if (decisionHash.isEmpty()) {
            revert EmptyDecisionHash();
        }
        if (resultHash.isEmpty()) {
            revert EmptyResultHash();
        }
        if (evidenceUri.isBlank()) {
            revert EmptyEvidenceUri();
        }
        if (action.isBlank()) {
            revert EmptyAction();
        }
        if (status.isBlank()) {
            revert EmptyStatus();
        }

        recordId = nextRecordId;
        records[recordId] = StrategyRecord({
            agentId: agentId,
            runId: runId,
            strategyId: strategyId,
            market: market,
            decisionHash: decisionHash,
            resultHash: resultHash,
            evidenceUri: evidenceUri,
            action: action,
            pnlBps: pnlBps,
            status: status,
            recorder: msg.sender,
            createdAt: block.timestamp
        });

        nextRecordId = recordId + 1;

        emit StrategyRecordRecorded(
            recordId,
            agentId,
            msg.sender,
            decisionHash,
            resultHash,
            runId,
            strategyId,
            market,
            evidenceUri,
            action,
            pnlBps,
            status
        );
    }

    function getRecord(uint256 recordId) external view returns (StrategyRecord memory) {
        if (recordId >= nextRecordId) {
            revert RecordNotFound(recordId);
        }

        return records[recordId];
    }
}
