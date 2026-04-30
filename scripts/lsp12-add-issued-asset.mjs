#!/usr/bin/env node

/**
 * lsp12-add-issued-asset.mjs
 * 
 * Append an LSP7/LSP8 asset address to LSP12IssuedAssets[] array on Agent UP.
 * 
 * Usage:
 *   CONTROLLER_PRIVATE_KEY=0x... RPC_URL=https://... \
 *     node lsp12-add-issued-asset.mjs <assetAddress>
 * 
 * Example:
 *   node lsp12-add-issued-asset.mjs 0xc831c970033FAe36c188F4495C3C57e8a7aD7623
 */

import { ethers } from 'ethers';

async function main() {
  const privateKey = process.env.CONTROLLER_PRIVATE_KEY;
  const rpcUrl = process.env.RPC_URL;
  
  if (!privateKey || !rpcUrl) {
    console.error('Required: CONTROLLER_PRIVATE_KEY and RPC_URL');
    process.exit(1);
  }

  const [assetAddress] = process.argv.slice(2);
  
  if (!assetAddress || !ethers.isAddress(assetAddress)) {
    console.error('Usage: node lsp12-add-issued-asset.mjs <assetAddress>');
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log('Controller:', wallet.address);
  console.log('Chain ID:', (await provider.getNetwork()).chainId.toString());
  console.log('Asset to add:', assetAddress);

  // Find agent UP
  const agentUP = await findAgentUP(wallet.address, provider);
  if (!agentUP) {
    console.error('No agent UP found for controller', wallet.address);
    process.exit(1);
  }

  const agentUPContract = new ethers.Contract(agentUP, ['function owner() view returns (address)', 'function getData(bytes32[]) view returns (bytes[])'], provider);
  const agentKM = await agentUPContract.owner();

  console.log('Agent UP:', agentUP);
  console.log('Agent KM:', agentKM);
  console.log('');

  // Read current LSP12IssuedAssets[]
  const LSP12_ARRAY_KEY = '0x7c8c3416d6cda87cd42c71ea1843df28ac4850354f988d55ee2eaa47b6dc05cd';
  const arrayLengthBytes = await agentUPContract.getData([LSP12_ARRAY_KEY]);
  const currentLength = arrayLengthBytes[0] === '0x' ? 0 : Number(ethers.toBigInt(arrayLengthBytes[0]));
  
  console.log('Current LSP12IssuedAssets[] length:', currentLength);

  // Check if already present
  const existingKeys = [];
  for (let i = 0; i < currentLength; i++) {
    existingKeys.push(LSP12_ARRAY_KEY.slice(0, 34) + ethers.zeroPadValue(ethers.toBeHex(i), 16).slice(2));
  }
  
  if (existingKeys.length > 0) {
    const existingValues = await agentUPContract.getData(existingKeys);
    const normalized = assetAddress.toLowerCase();
    for (let i = 0; i < existingValues.length; i++) {
      if (existingValues[i].toLowerCase() === normalized) {
        console.log(`✅ Asset already in LSP12IssuedAssets[] at index ${i}`);
        return;
      }
    }
  }

  // Append: set array[length] = assetAddress, then increment length
  const newIndex = currentLength;
  const newLength = currentLength + 1;
  
  const newElementKey = LSP12_ARRAY_KEY.slice(0, 34) + ethers.zeroPadValue(ethers.toBeHex(newIndex), 16).slice(2);
  const newElementValue = assetAddress.toLowerCase();
  
  const newLengthValue = ethers.zeroPadValue(ethers.toBeHex(newLength), 16);

  // Detect asset type (LSP7 vs LSP8)
  const assetContract = new ethers.Contract(assetAddress, ['function supportsInterface(bytes4) view returns (bool)'], provider);
  let interfaceId;
  try {
    const isLSP7 = await assetContract.supportsInterface('0xda1f85e4'); // LSP7DigitalAsset
    const isLSP8 = await assetContract.supportsInterface('0x3a271706'); // LSP8IdentifiableDigitalAsset
    
    if (isLSP8) {
      interfaceId = '0x3a271706';
      console.log('Detected LSP8IdentifiableDigitalAsset');
    } else if (isLSP7) {
      interfaceId = '0xda1f85e4';
      console.log('Detected LSP7DigitalAsset');
    } else {
      console.error('Asset does not support LSP7 or LSP8 interface');
      process.exit(1);
    }
  } catch (e) {
    console.error('Failed to detect asset interface:', e.message);
    process.exit(1);
  }

  // LSP12IssuedAssetsMap:<address> = (bytes4 interfaceId, uint128 index)
  const mapKey = '0x74ac2555c10b9349e78f0000' + assetAddress.slice(2).toLowerCase();
  const mapValue = interfaceId + ethers.zeroPadValue(ethers.toBeHex(newIndex), 16).slice(2);

  console.log('Setting:');
  console.log('  Array length:', newLengthValue);
  console.log('  Array element:', newElementKey, '→', newElementValue);
  console.log('  Map entry:', mapKey, '→', mapValue);
  console.log('');

  // Build setDataBatch calldata
  const setDataBatchABI = ['function setDataBatch(bytes32[] memory dataKeys, bytes[] memory dataValues)'];
  const iface = new ethers.Interface(setDataBatchABI);
  const setDataBatchCalldata = iface.encodeFunctionData('setDataBatch', [
    [LSP12_ARRAY_KEY, newElementKey, mapKey],
    [newLengthValue, newElementValue, mapValue]
  ]);

  // Execute via KM
  const kmIface = new ethers.Interface(['function execute(bytes) payable returns (bytes)']);
  const kmCalldata = kmIface.encodeFunctionData('execute', [setDataBatchCalldata]);

  const km = new ethers.Contract(agentKM, ['function execute(bytes) payable returns (bytes)'], wallet);

  console.log('Executing: EOA → Agent KM → Agent UP.setDataBatch()');

  const gas = await km.execute.estimateGas(kmCalldata);
  console.log('Gas estimate:', gas.toString());

  const tx = await km.execute(kmCalldata, { gasLimit: gas * 150n / 100n });
  console.log('TX:', tx.hash);

  const receipt = await tx.wait();
  console.log('✅ Confirmed! Block:', receipt.blockNumber);

  // Verify
  const finalLength = await agentUPContract.getData([LSP12_ARRAY_KEY]);
  console.log('New LSP12IssuedAssets[] length:', Number(ethers.toBigInt(finalLength[0])));
}

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
      if (perms && perms !== '0x' && BigInt(perms) > 0n) return upAddr;
    } catch (e) {}
  }
  return null;
}

main().catch(err => {
  console.error('Error:', err.reason || err.message);
  process.exit(1);
});
