import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const PrivacyPreservingBountyJudgeModule = buildModule(
  "PrivacyPreservingBountyJudgeModule",
  (m) => {
    const judge = m.contract("PrivacyPreservingBountyJudge");

    return { judge };
  }
);

export default PrivacyPreservingBountyJudgeModule;