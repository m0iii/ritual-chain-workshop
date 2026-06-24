# Privacy-Preserving AI Bounty Judge Homework

## 1. What This Assignment Is About

This assignment extends the original AI Bounty Judge workshop app so that bounty submissions are not publicly visible during the submission phase.

In the original version, participants could submit answers directly, but those answers became public immediately. This creates an unfair situation because later participants can read earlier answers, copy useful ideas, and submit improved versions.

The goal of this homework is to make the bounty process more fair by hiding answers until the correct phase. The required solution uses a commit-reveal flow in Solidity. The advanced design note explains how a more Ritual-native version could keep answers encrypted and judge them privately inside a TEE-backed workflow.

## 2. Required Track: Commit-Reveal Structure

The required track uses a commit-reveal flow.

Instead of submitting the full answer immediately, each participant first submits only a commitment hash. This commitment proves that the participant had an answer at submission time, but it does not reveal the answer itself.

The commitment is generated using:

```solidity
bytes32 commitment = keccak256(
    abi.encodePacked(answer, salt, msg.sender, bountyId)
);
```

This includes four values:

* `answer`: the participant’s actual answer
* `salt`: a secret random value chosen by the participant
* `msg.sender`: the participant’s wallet address
* `bountyId`: the specific bounty being submitted to

Including `msg.sender` and `bountyId` helps prevent another participant from copying a commitment and trying to reuse it for a different participant or bounty.

After the submission deadline passes, participants reveal their answer and salt. The contract recomputes the hash and checks whether it matches the original commitment. If the hash matches, the reveal is valid. If it does not match, the reveal is rejected.

Only valid revealed answers are eligible for AI judging.

## 3. Bounty Lifecycle

The new bounty lifecycle works like this:

1. The bounty owner creates a bounty with a reward, a submission deadline, and a reveal deadline.
2. Participants submit only a commitment hash during the submission phase.
3. The real answers remain hidden during the submission phase.
4. After the submission deadline, participants reveal their answer and salt.
5. The contract verifies that the revealed answer and salt match the original commitment.
6. Only valid revealed answers become eligible for judging.
7. After the reveal deadline, the bounty owner calls `judgeAll`.
8. The revealed answers are judged together in one batch AI judging request.
9. The AI recommends a result.
10. The bounty owner finalizes the winner.
11. The contract pays the reward to the finalized winner.

This structure improves fairness because participants cannot see each other’s answers before the submission deadline.

## 4. Required Contract Functions

The required functions are:

```solidity
function submitCommitment(uint256 bountyId, bytes32 commitment) external;

function revealAnswer(
    uint256 bountyId,
    string calldata answer,
    bytes32 salt
) external;

function judgeAll(uint256 bountyId, bytes calldata llmInput) external;

function finalizeWinner(uint256 bountyId, uint256 winnerIndex) external;
```

### submitCommitment

This function allows a participant to submit a commitment hash before the submission deadline.

Rules:

* It can only be called before the submission deadline.
* Each participant can submit only one commitment per bounty.
* The commitment must not be empty.
* The answer itself is not stored or revealed at this stage.

### revealAnswer

This function allows a participant to reveal their answer and salt after the submission deadline and before the reveal deadline.

Rules:

* It can only be called during the reveal phase.
* The participant must already have submitted a commitment.
* The participant cannot reveal twice.
* The contract checks whether `keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))` matches the stored commitment.
* If the hash matches, the answer becomes a valid revealed submission.
* If the hash does not match, the reveal is rejected.

### judgeAll

This function allows the bounty owner to start AI judging after the reveal deadline.

Rules:

* Only the bounty owner can call it.
* It can only be called after the reveal deadline.
* It should judge only valid revealed answers.
* It should use batch judging instead of calling the LLM once per submission.
* It marks the bounty as judged.

### finalizeWinner

This function allows the bounty owner to finalize the winner after judging is complete.

Rules:

* Only the bounty owner can call it.
* It can only be called after judging is complete.
* It can only be called once.
* The winner must be selected from valid revealed submissions.
* The reward should be paid only once.

## 5. Test Plan

The following test plan covers important valid and invalid cases.

### Commitment Submission Tests

1. A participant can submit a commitment before the submission deadline.
2. A participant cannot submit a commitment after the submission deadline.
3. A participant cannot submit more than one commitment for the same bounty.
4. A zero commitment should be rejected.

### Reveal Tests

1. A participant can reveal after the submission deadline and before the reveal deadline.
2. A reveal with the correct answer and salt should be accepted.
3. A reveal with the wrong salt should be rejected.
4. A reveal with the wrong answer should be rejected.
5. A participant cannot reveal before the submission deadline.
6. A participant cannot reveal after the reveal deadline.
7. A participant who never submitted a commitment cannot reveal.
8. A participant cannot reveal twice.

### Judging Tests

1. The bounty owner can call `judgeAll` only after the reveal deadline.
2. A non-owner cannot call `judgeAll`.
3. Unrevealed submissions are not eligible for judging.
4. Only valid revealed answers should be included in the judging process.
5. The system should use one batch judging request instead of one AI request per answer.

### Finalization Tests

1. The bounty owner can finalize a winner only after judging is complete.
2. A non-owner cannot finalize the winner.
3. The winner must be a valid revealed submission.
4. The reward can only be paid once.
5. The bounty cannot be finalized twice.

## 6. Advanced Ritual-Native Design Note

The commit-reveal solution improves fairness because answers are hidden during the submission phase. However, it still has one limitation: answers become public during the reveal phase before AI judging is fully complete.

A more Ritual-native design could keep answers hidden for longer by using encrypted submissions and TEE-backed execution.

In this advanced design, each participant would encrypt their answer before submitting it. The smart contract would store only encrypted answers or references to encrypted off-chain storage. Plaintext answers would not be visible on-chain during the submission or reveal process.

The plaintext answers would exist only inside a trusted execution environment during the judging step. A Ritual TEE-backed executor could decrypt all submissions privately and send them to the LLM together in one batch judging request. This would allow the AI to compare all answers without exposing them publicly before judging.

The on-chain contract would store public metadata such as the bounty ID, deadlines, participants, encrypted submission references, and hashes. The actual plaintext answers could be stored off-chain and revealed later as a final answer bundle.

After judging is complete, the system could publish:

```json
{
  "winnerIndex": 2,
  "ranking": [
    {
      "index": 2,
      "score": 94,
      "reason": "Best satisfies the rubric."
    }
  ],
  "revealedAnswersRef": "ipfs://example-bundle",
  "revealedAnswersHash": "0x...",
  "summary": "Submission 2 is the strongest answer."
}
```

The contract would not need to store all plaintext answers directly on-chain. Instead, it could store a reference to the revealed answer bundle and a hash of that bundle. This helps reduce gas cost while still allowing people to verify that the final revealed bundle matches the committed judging result.

In this design, Ritual is used for more than simply calling an LLM. It supports private AI evaluation by allowing sensitive inputs to be handled inside a protected execution environment. This better matches the goal of privacy-preserving AI judging.

## 7. Commit-Reveal vs Ritual-Native Encrypted Submissions

### Commit-Reveal

Commit-reveal works on any EVM chain. It is simple, transparent, and easier to implement in Solidity. Participants submit a hash first and reveal the answer later.

The main advantage is fairness during the submission phase. Other participants cannot copy answers before the submission deadline.

The limitation is that answers become public during the reveal phase before or during the judging process.

### Ritual-Native Encrypted Submissions

A Ritual-native encrypted submission system can keep answers hidden until the AI judging step is complete. Participants submit encrypted answers or encrypted references, and the plaintext is only handled inside a TEE-backed workflow.

The main advantage is stronger privacy. Other participants cannot read the answers before judging.

The limitation is that the design is more complex. It requires encrypted input handling, off-chain storage decisions, TEE-based execution, and a clear way to commit to the final revealed answer bundle.

## 8. Reflection Question

In a bounty system, the bounty description, reward amount, deadlines, rules, and final winner should be public because participants need to trust that the process is fair. However, the actual answers should stay hidden during the submission phase so that later participants cannot copy earlier work. Commitments can be public because they prove that a participant submitted something without revealing the answer itself. AI should help evaluate the revealed answers according to the bounty rubric, especially when many submissions need to be compared together. However, the AI should not automatically control the payout unless the result is clearly parsed and validated. A human bounty owner should make the final decision because they are responsible for confirming that the AI recommendation makes sense. This creates a balance where the smart contract enforces fairness, AI helps with judging, and humans keep final accountability.

## 9. Summary

This homework adds privacy and fairness to the AI Bounty Judge system.

The required implementation uses a commit-reveal flow so answers remain hidden during the submission phase. Participants first submit a commitment hash, then reveal their answer and salt later. The contract verifies the reveal and only valid revealed answers are eligible for judging.

The advanced Ritual-native design shows how encrypted submissions could be judged privately using TEE-backed execution and batch AI evaluation.
