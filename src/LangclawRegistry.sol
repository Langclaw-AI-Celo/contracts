// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract LangclawRegistry {
    struct AgentDecision {
        uint256 agentId;
        string runId;
        bytes32 decisionHash;
        string evidenceUri;
        string signalType;
        address recorder;
        uint256 createdAt;
    }

    uint256 public nextDecisionId;

    mapping(uint256 => AgentDecision) private decisions;

    event AgentDecisionRecorded(
        uint256 indexed decisionId,
        uint256 indexed agentId,
        address indexed recorder,
        bytes32 decisionHash,
        string runId,
        string evidenceUri,
        string signalType
    );

    error EmptyRunId();
    error EmptyDecisionHash();
    error EmptyEvidenceUri();
    error EmptySignalType();
    error DecisionNotFound(uint256 decisionId);

    function recordAgentDecision(
        uint256 agentId,
        string calldata runId,
        bytes32 decisionHash,
        string calldata evidenceUri,
        string calldata signalType
    ) external returns (uint256 decisionId) {
        if (bytes(runId).length == 0) {
            revert EmptyRunId();
        }

        if (decisionHash == bytes32(0)) {
            revert EmptyDecisionHash();
        }

        if (bytes(evidenceUri).length == 0) {
            revert EmptyEvidenceUri();
        }

        if (bytes(signalType).length == 0) {
            revert EmptySignalType();
        }

        decisionId = nextDecisionId;
        decisions[decisionId] = AgentDecision({
            agentId: agentId,
            runId: runId,
            decisionHash: decisionHash,
            evidenceUri: evidenceUri,
            signalType: signalType,
            recorder: msg.sender,
            createdAt: block.timestamp
        });

        nextDecisionId = decisionId + 1;

        emit AgentDecisionRecorded(
            decisionId,
            agentId,
            msg.sender,
            decisionHash,
            runId,
            evidenceUri,
            signalType
        );
    }

    function getDecision(uint256 decisionId) external view returns (AgentDecision memory) {
        if (decisionId >= nextDecisionId) {
            revert DecisionNotFound(decisionId);
        }

        return decisions[decisionId];
    }
}
