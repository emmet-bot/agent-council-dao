#!/usr/bin/env node

/**
 * council-register-8004.mjs
 * 
 * Register the Agent Council in the ERC-8004 AgentIdentity registry.
 * 
 * NOTE: The council UP doesn't implement onERC721Received, so _safeMint 
 * reverts when minting directly to it. This script registers from the 
 * controller EOA and then transfers ownership to the council UP using 
 * transferFrom (which skips the onERC721Received check).
 * 
 * For future reference: if the UP implementation is updated to support
 * ERC721Receiver, the 4-hop chain through council-execute.mjs can be 
 * used instead.
 * 
 * Usage:
 *   CONTROLLER_PRIVATE_KEY=0x... RPC_URL=https://... \
 *     node council-register-8004.mjs <agentURI>
 * 
 * Example:
 *   node council-register-8004.mjs "https://api.universalprofile.cloud/ipfs/QmXYZ..."
 */

import { ethers } from 'ethers';

const COUNCIL_UP = '0x888033b1492161b5f867573d675d178fa56854ae';
const ERC8004_REGISTRY = '0x8004A169FB4a3325136EB29fA0ceB6D2e539a432';

async function main() {
  const privateKey = process.env.CONTROLLER_PRIVATE_KEY;
  const rpcUrl = process.env.RPC_URL;
  
  if (!privateKey || !rpcUrl) {
    console.error('Required: CONTROLLER_PRIVATE_KEY and RPC_URL');
    process.exit(1);
  }

  const agentURI = process.argv[2];
  if (!agentURI) {
    console.error('Usage: node council-register-8004.mjs <agentURI>');
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  const network = await provider.getNetwork();
  
  console.log('Controller:', wallet.address);
  console.log('Chain ID:', network.chainId.toString());
  console.log('URI:', agentURI);
  console.log('');

  const balance = await provider.getBalance(wallet.address);
  console.log('Balance:', ethers.formatEther(balance), 'ETH');

  const abi = [
    'function register(string agentURI) external returns (uint256)',
    'function transferFrom(address from, address to, uint256 tokenId) external',
    'function ownerOf(uint256 tokenId) view returns (address)',
    'function balanceOf(address owner) view returns (uint256)',
  ];
  const registry = new ethers.Contract(ERC8004_REGISTRY, abi, wallet);

  // Check if council already has a registration
  const existing = await registry.balanceOf(COUNCIL_UP);
  if (existing > 0n) {
    console.log(`Council already has ${existing} registration(s) on this chain.`);
    console.log('Use council-execute.mjs with setAgentURI to update metadata.');
    process.exit(0);
  }

  // Step 1: Register from EOA
  console.log('\nStep 1: Registering...');
  const gas = await registry.register.estimateGas(agentURI);
  console.log('Gas estimate:', gas.toString());

  const tx1 = await registry.register(agentURI, { gasLimit: gas * 150n / 100n });
  console.log('TX:', tx1.hash);
  const receipt1 = await tx1.wait();

  // Extract agentId from Transfer event
  const transferTopic = ethers.id('Transfer(address,address,uint256)');
  const transferLog = receipt1.logs.find(l => l.topics[0] === transferTopic);
  const agentId = ethers.toBigInt(transferLog.topics[3]);
  console.log('Agent ID:', agentId.toString());

  // Step 2: Transfer to council UP
  console.log('\nStep 2: Transferring to council UP...');
  const tx2 = await registry.transferFrom(wallet.address, COUNCIL_UP, agentId);
  console.log('TX:', tx2.hash);
  await tx2.wait();

  // Verify
  const owner = await registry.ownerOf(agentId);
  console.log('\n✅ Registration complete!');
  console.log('Agent ID:', agentId.toString());
  console.log('Owner:', owner);
  console.log('Chain:', network.chainId.toString());
}

main().catch(err => {
  console.error('Error:', err.reason || err.message);
  process.exit(1);
});
