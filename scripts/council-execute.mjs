#!/usr/bin/env node

/**
 * council-execute.mjs
 * 
 * Execute any contract call through the Agent Council UP.
 * 
 * Flow: Agent EOA → Agent KM → Agent UP → Council KM → Council UP → Target
 * 
 * Usage:
 *   CONTROLLER_PRIVATE_KEY=0x... RPC_URL=https://... \
 *     node council-execute.mjs <targetAddress> <calldata> [value]
 * 
 * Example — call setAgentURI on ERC-8004:
 *   node council-execute.mjs \
 *     0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \
 *     $(node -e "console.log(new (require('ethers').Interface)(['function setAgentURI(uint256,string)']).encodeFunctionData('setAgentURI', [35302, 'https://...']))")
 */

import { ethers } from 'ethers';

// --- Config ---
const COUNCIL_UP = '0x888033b1492161b5f867573d675d178fa56854ae';
const COUNCIL_KM = '0xE64355744bEdF04757E5b6A340412EAB06b8aF29';

const UP_EXECUTE_ABI = ['function execute(uint256 operationType, address target, uint256 value, bytes data) returns (bytes)'];
const KM_EXECUTE_ABI = ['function execute(bytes calldata) payable returns (bytes)'];
const OWNER_ABI = ['function owner() view returns (address)'];

// --- Main ---
async function main() {
  const privateKey = process.env.CONTROLLER_PRIVATE_KEY;
  const rpcUrl = process.env.RPC_URL;
  
  if (!privateKey || !rpcUrl) {
    console.error('Required: CONTROLLER_PRIVATE_KEY and RPC_URL environment variables');
    process.exit(1);
  }

  const [targetAddress, calldata, value = '0'] = process.argv.slice(2);
  
  if (!targetAddress || !calldata) {
    console.error('Usage: node council-execute.mjs <targetAddress> <calldata> [valueInWei]');
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log('Controller:', wallet.address);
  console.log('Target:', targetAddress);
  console.log('Chain ID:', (await provider.getNetwork()).chainId.toString());

  // Resolve the agent's KeyManager
  const agentUP = await findAgentUP(wallet.address, provider);
  if (!agentUP) {
    console.error('Could not find an agent UP controlled by', wallet.address);
    process.exit(1);
  }
  
  const agentUPContract = new ethers.Contract(agentUP, OWNER_ABI, provider);
  const agentKM = await agentUPContract.owner();
  
  console.log('Agent UP:', agentUP);
  console.log('Agent KM:', agentKM);
  console.log('');

  // Build the 4-hop calldata
  const upIface = new ethers.Interface(UP_EXECUTE_ABI);
  const kmIface = new ethers.Interface(KM_EXECUTE_ABI);

  // Layer 1: Council UP calls target
  const councilExec = upIface.encodeFunctionData('execute', [
    0, // CALL
    targetAddress,
    BigInt(value),
    calldata
  ]);

  // Layer 2: Council KM executes on council UP
  const councilKMExec = kmIface.encodeFunctionData('execute', [councilExec]);

  // Layer 3: Agent UP calls council KM
  const agentUPExec = upIface.encodeFunctionData('execute', [
    0, // CALL
    COUNCIL_KM,
    0n,
    councilKMExec
  ]);

  // Layer 4: Agent KM executes on agent UP
  const km = new ethers.Contract(agentKM, KM_EXECUTE_ABI, wallet);

  console.log('Executing: EOA → Agent KM → Agent UP → Council KM → Council UP → Target');

  const gas = await km.execute.estimateGas(agentUPExec);
  console.log('Gas estimate:', gas.toString());

  const tx = await km.execute(agentUPExec, { gasLimit: gas * 150n / 100n });
  console.log('TX:', tx.hash);
  
  const receipt = await tx.wait();
  console.log('Confirmed! Block:', receipt.blockNumber, 'Gas used:', receipt.gasUsed.toString());
  
  return receipt;
}

/**
 * Find which agent UP this controller EOA belongs to.
 * Checks known agent UPs for ownership chain.
 */
async function findAgentUP(controllerAddress, provider) {
  const AGENT_UPS = [
    '0x1089E1c613Db8Cb91db72be4818632153E62557a', // Emmet
    '0x293E96ebbf264ed7715cff2b67850517De70232a', // LUKSOAgent
    '0x1e0267B7e88B97d5037e410bdC61D105e04ca02A', // Leo
    '0xDb4DAD79d8508656C6176408B25BEAd5d383E450', // Ampy
  ];

  const abi = ['function getData(bytes32) view returns (bytes)'];
  
  for (const upAddr of AGENT_UPS) {
    const up = new ethers.Contract(upAddr, abi, provider);
    const permKey = '0x4b80742de2bf82acb3630000' + controllerAddress.slice(2).toLowerCase();
    try {
      const perms = await up.getData(permKey);
      if (perms && perms !== '0x' && BigInt(perms) > 0n) {
        return upAddr;
      }
    } catch (e) {
      // Skip if contract doesn't exist on this chain
    }
  }
  return null;
}

main().catch(err => {
  console.error('Error:', err.reason || err.message);
  process.exit(1);
});
