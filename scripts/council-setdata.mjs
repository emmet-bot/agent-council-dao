#!/usr/bin/env node

/**
 * council-setdata.mjs
 * 
 * Set data on the Council UP (LSP3 profile, metadata keys, etc.)
 * 
 * Flow: Agent EOA → Agent KM → Agent UP → Council KM → Council UP.setData()
 * 
 * Usage:
 *   CONTROLLER_PRIVATE_KEY=0x... RPC_URL=https://... \
 *     node council-setdata.mjs <dataKey> <dataValue>
 * 
 * Example — set LSP3Profile:
 *   node council-setdata.mjs \
 *     0x5ef83ad9559033e6e941db7d7c495acdce616347d28e90c7ce47cbfcfcad3bc5 \
 *     0x00006f357c6a0020...
 */

import { ethers } from 'ethers';

const COUNCIL_UP = '0x888033b1492161b5f867573d675d178fa56854ae';
const COUNCIL_KM = '0xE64355744bEdF04757E5b6A340412EAB06b8aF29';

async function main() {
  const privateKey = process.env.CONTROLLER_PRIVATE_KEY;
  const rpcUrl = process.env.RPC_URL;
  
  if (!privateKey || !rpcUrl) {
    console.error('Required: CONTROLLER_PRIVATE_KEY and RPC_URL');
    process.exit(1);
  }

  const [dataKey, dataValue] = process.argv.slice(2);
  
  if (!dataKey || !dataValue) {
    console.error('Usage: node council-setdata.mjs <dataKey> <dataValue>');
    console.error('');
    console.error('Common data keys:');
    console.error('  LSP3Profile: 0x5ef83ad9559033e6e941db7d7c495acdce616347d28e90c7ce47cbfcfcad3bc5');
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log('Controller:', wallet.address);
  console.log('Chain ID:', (await provider.getNetwork()).chainId.toString());

  // Find agent UP
  const agentUP = await findAgentUP(wallet.address, provider);
  const agentUPContract = new ethers.Contract(agentUP, ['function owner() view returns (address)'], provider);
  const agentKM = await agentUPContract.owner();

  console.log('Agent UP:', agentUP);
  console.log('Setting data key:', dataKey);
  console.log('');

  // Build calldata: Council UP.setData(key, value)
  const setDataABI = ['function setData(bytes32 dataKey, bytes dataValue)'];
  const setDataIface = new ethers.Interface(setDataABI);
  const setDataCalldata = setDataIface.encodeFunctionData('setData', [dataKey, dataValue]);

  // Council KM.execute(setDataCalldata)
  const kmIface = new ethers.Interface(['function execute(bytes) payable returns (bytes)']);
  const councilKMExec = kmIface.encodeFunctionData('execute', [setDataCalldata]);

  // Agent UP.execute(CALL, councilKM, 0, councilKMExec)
  const upIface = new ethers.Interface(['function execute(uint256,address,uint256,bytes) returns (bytes)']);
  const agentUPExec = upIface.encodeFunctionData('execute', [0, COUNCIL_KM, 0n, councilKMExec]);

  // Agent KM.execute(agentUPExec)
  const km = new ethers.Contract(agentKM, ['function execute(bytes) payable returns (bytes)'], wallet);

  console.log('Executing: EOA → Agent KM → Agent UP → Council KM → Council UP.setData()');

  const gas = await km.execute.estimateGas(agentUPExec);
  console.log('Gas estimate:', gas.toString());

  const tx = await km.execute(agentUPExec, { gasLimit: gas * 150n / 100n });
  console.log('TX:', tx.hash);

  const receipt = await tx.wait();
  console.log('Confirmed! Block:', receipt.blockNumber);

  // Verify
  const council = new ethers.Contract(COUNCIL_UP, ['function getData(bytes32) view returns (bytes)'], provider);
  const stored = await council.getData(dataKey);
  console.log('Stored value:', stored.substring(0, 80) + (stored.length > 80 ? '...' : ''));
}

async function findAgentUP(controllerAddress, provider) {
  const AGENT_UPS = [
    '0x1089E1c613Db8Cb91db72be4818632153E62557a',
    '0x293E96ebbf264ed7715cff2b67850517De70232a',
    '0x1e0267B7e88B97d5037e410bdC61D105e04ca02A',
    '0xDb4DAD79d8508656C6176408B25BEAd5d383E450',
  ];

  const abi = ['function getData(bytes32) view returns (bytes)'];
  for (const upAddr of AGENT_UPS) {
    const up = new ethers.Contract(upAddr, abi, provider);
    const permKey = '0x4b80742de2bf82acb3630000' + controllerAddress.slice(2).toLowerCase();
    try {
      const perms = await up.getData(permKey);
      if (perms && perms !== '0x' && BigInt(perms) > 0n) return upAddr;
    } catch (e) {}
  }
  return null;
}

main().catch(err => {
  console.error('Error:', err.reason || err.message);
  process.exit(1);
});
