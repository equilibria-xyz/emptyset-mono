import HRE from 'hardhat'
import { HardhatConfig } from 'hardhat/types'
import { mine, time } from '@nomicfoundation/hardhat-network-helpers'
const { ethers } = HRE

export async function currentBlockTimestamp(): Promise<number> {
  const blockNumber = await ethers.provider.getBlockNumber()
  const block = await ethers.provider.getBlock(blockNumber)
  return block.timestamp
}

export async function mineBlock(): Promise<void> {
  await mine()
}

export async function mineTo(block: number): Promise<void> {
  mine((await ethers.provider.getBlockNumber()) - block)
}

export async function increase(duration: number): Promise<void> {
  await time.increase(duration)
  await mineBlock()
}

export async function reset(config: HardhatConfig): Promise<void> {
  await ethers.provider.send('hardhat_reset', [
    {
      forking: {
        jsonRpcUrl: config.networks?.hardhat?.forking?.url,
        blockNumber: config.networks?.hardhat?.forking?.blockNumber,
      },
    },
  ])
}
