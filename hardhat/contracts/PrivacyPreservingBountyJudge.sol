// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract PrivacyPreservingBountyJudge {
    uint256 public nextBountyId = 1;

    struct Bounty {
        address owner;
        string title;
        string rubric;
        uint256 reward;
        uint256 submissionDeadline;
        uint256 revealDeadline;
        bool judged;
        bool finalized;
        uint256 winnerIndex;
    }

    struct Submission {
        address submitter;
        bytes32 commitment;
        string answer;
        bool revealed;
        bool exists;
        bool eligible;
    }

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => mapping(address => Submission)) public submissions;
    mapping(uint256 => address[]) public participants;
    mapping(uint256 => address[]) public revealedParticipants;

    event BountyCreated(
        uint256 indexed bountyId,
        address indexed owner,
        string title,
        uint256 reward,
        uint256 submissionDeadline,
        uint256 revealDeadline
    );

    event CommitmentSubmitted(
        uint256 indexed bountyId,
        address indexed submitter,
        bytes32 commitment
    );

    event AnswerRevealed(
        uint256 indexed bountyId,
        address indexed submitter,
        uint256 revealedIndex
    );

    event JudgingCompleted(
        uint256 indexed bountyId,
        bytes llmInput
    );

    event WinnerFinalized(
        uint256 indexed bountyId,
        address indexed winner,
        uint256 winnerIndex,
        uint256 reward
    );

    modifier onlyBountyOwner(uint256 bountyId) {
        require(bounties[bountyId].owner == msg.sender, "Only bounty owner");
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        require(bounties[bountyId].owner != address(0), "Bounty does not exist");
        _;
    }

    function createBounty(
        string calldata title,
        string calldata rubric,
        uint256 submissionDeadline,
        uint256 revealDeadline
    ) external payable returns (uint256 bountyId) {
        require(msg.value > 0, "Reward required");
        require(submissionDeadline > block.timestamp, "Invalid submission deadline");
        require(revealDeadline > submissionDeadline, "Invalid reveal deadline");

        bountyId = nextBountyId++;

        bounties[bountyId] = Bounty({
            owner: msg.sender,
            title: title,
            rubric: rubric,
            reward: msg.value,
            submissionDeadline: submissionDeadline,
            revealDeadline: revealDeadline,
            judged: false,
            finalized: false,
            winnerIndex: 0
        });

        emit BountyCreated(
            bountyId,
            msg.sender,
            title,
            msg.value,
            submissionDeadline,
            revealDeadline
        );
    }

    function submitCommitment(
        uint256 bountyId,
        bytes32 commitment
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(block.timestamp < bounty.submissionDeadline, "Submission closed");
        require(commitment != bytes32(0), "Invalid commitment");
        require(!submissions[bountyId][msg.sender].exists, "Already submitted");

        submissions[bountyId][msg.sender] = Submission({
            submitter: msg.sender,
            commitment: commitment,
            answer: "",
            revealed: false,
            exists: true,
            eligible: false
        });

        participants[bountyId].push(msg.sender);

        emit CommitmentSubmitted(bountyId, msg.sender, commitment);
    }

    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        Submission storage submission = submissions[bountyId][msg.sender];

        require(block.timestamp >= bounty.submissionDeadline, "Reveal not started");
        require(block.timestamp < bounty.revealDeadline, "Reveal closed");
        require(submission.exists, "No commitment found");
        require(!submission.revealed, "Already revealed");
        require(bytes(answer).length > 0, "Empty answer");

        bytes32 computedCommitment = keccak256(
            abi.encodePacked(answer, salt, msg.sender, bountyId)
        );

        require(computedCommitment == submission.commitment, "Invalid reveal");

        submission.answer = answer;
        submission.revealed = true;
        submission.eligible = true;

        revealedParticipants[bountyId].push(msg.sender);

        emit AnswerRevealed(
            bountyId,
            msg.sender,
            revealedParticipants[bountyId].length - 1
        );
    }

    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external bountyExists(bountyId) onlyBountyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(block.timestamp >= bounty.revealDeadline, "Reveal phase not ended");
        require(!bounty.judged, "Already judged");
        require(revealedParticipants[bountyId].length > 0, "No revealed submissions");

        bounty.judged = true;

        emit JudgingCompleted(bountyId, llmInput);
    }

    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    ) external bountyExists(bountyId) onlyBountyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(bounty.judged, "Judging not complete");
        require(!bounty.finalized, "Already finalized");
        require(winnerIndex < revealedParticipants[bountyId].length, "Invalid winner index");

        address winner = revealedParticipants[bountyId][winnerIndex];
        require(winner != address(0), "Invalid winner");

        bounty.finalized = true;
        bounty.winnerIndex = winnerIndex;

        uint256 reward = bounty.reward;
        bounty.reward = 0;

        (bool success, ) = payable(winner).call{value: reward}("");
        require(success, "Reward transfer failed");

        emit WinnerFinalized(bountyId, winner, winnerIndex, reward);
    }

    function getParticipantCount(uint256 bountyId) external view returns (uint256) {
        return participants[bountyId].length;
    }

    function getRevealedParticipantCount(uint256 bountyId) external view returns (uint256) {
        return revealedParticipants[bountyId].length;
    }

    function getRevealedParticipant(
        uint256 bountyId,
        uint256 index
    ) external view returns (address) {
        require(index < revealedParticipants[bountyId].length, "Invalid index");
        return revealedParticipants[bountyId][index];
    }

    function getSubmission(
        uint256 bountyId,
        address submitter
    )
        external
        view
        returns (
            bytes32 commitment,
            string memory answer,
            bool revealed,
            bool eligible
        )
    {
        Submission storage submission = submissions[bountyId][submitter];

        return (
            submission.commitment,
            submission.answer,
            submission.revealed,
            submission.eligible
        );
    }
}