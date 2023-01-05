import { dirname } from 'path'
import defaultConfig from '../common/hardhat.default.config'

const dsuDir = dirname(require.resolve('@emptyset/dsu/package.json'))

const config = defaultConfig({
  externalDeployments: {
    kovan: [`${dsuDir}/deployments/kovan`],
    goerli: [`${dsuDir}/deployments/goerli`],
    optimismGoerli: [`${dsuDir}/deployments/optimismGoerli`],
    arbitrumGoerli: [`${dsuDir}/deployments/arbitrumGoerli`],
    mainnet: [`${dsuDir}/deployments/mainnet`],
    hardhat: [`${dsuDir}/deployments/mainnet`],
    localhost: [`${dsuDir}/deployments/localhost`],
  },
  dependencyPaths: [
    '@emptyset/dsu/contracts/DSU.sol',
    '@equilibria/root/control/unstructured/CrossChainOwner/UCrossChainOwner_Arbitrum.sol',
    '@equilibria/root/control/unstructured/CrossChainOwner/UCrossChainOwner_Optimism.sol',
    '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol',
    '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol',
  ],
})

export default config
