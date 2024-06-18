import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const JAN_1ST_2030 = 1893456000;
const ONE_GWEI: bigint = 1_000_000_000n;

const FWSModule = buildModule("FWSModule", (m) => {
  // const unlockTime = m.getParameter("unlockTime", JAN_1ST_2030);
  // const lockedAmount = m.getParameter("lockedAmount", ONE_GWEI);

  const escrow = m.contract("Escrow", [], {});
  const dealSLA = m.contract("DealSLANoCurrentFault", [], {});
  const simplePDP = m.contract("SimplePDPService", [escrow], {})

  return { escrow, dealSLA };
});

export default FWSModule;
