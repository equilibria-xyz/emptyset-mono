import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber, BigNumberish } from 'ethers'
import { impersonateAccount, setBalance } from '@nomicfoundation/hardhat-network-helpers'
import HRE from 'hardhat'
const { ethers } = HRE

export async function impersonate(address: string): Promise<SignerWithAddress> {
  await impersonateAccount(address)
  return ethers.getSigner(address)
}

export async function impersonateWithBalance(address: string, balance: BigNumberish): Promise<SignerWithAddress> {
  await setBalance(address, BigNumber.from(balance))
  return impersonate(address)
}
