import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { DSU__factory } from '../types/generated'
import { isOptimism } from '../../common/testutil/network'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deploy, get } = deployments
  const { deployer } = await getNamedAccounts()
  const deployerSigner = await ethers.getSigner(deployer)

  const usdc = await get('USDC')
  const usdcBridged = await get('USDCBridged')
  const dsu = new DSU__factory(deployerSigner).attach((await get('DSU')).address)
  console.log(`Using DSU at ${dsu.address}`)
  console.log(`Using USDC at ${usdc.address}`)
  console.log(`Using USDCBridged at ${usdcBridged.address}`)
  if (!isOptimism(network.name)) throw new Error('This migration is only for Arbitrum')

  await deploy('MigrationReserveImpl', {
    contract: 'MigrationReserve',
    args: [dsu.address, usdc.address, usdcBridged.address],
    from: deployer,
    skipIfAlreadyDeployed: true,
    log: true,
    autoMine: true,
  })
}

export default func
func.tags = ['Deploy_MigrationReserve_Optimism']
