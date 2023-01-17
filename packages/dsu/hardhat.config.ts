import { dirname } from 'path'
import defaultConfig from '../common/hardhat.default.config'

// DSU is only a dev dependency so may not exist
let dsuDir = ''
try {
  dsuDir = dirname(require.resolve('@emptyset/reserve/package.json'))
} catch {
  // pass
}

const config = defaultConfig({
  externalDeployments: {
    kovan: [`${dsuDir}/deployments/kovan`],
    goerli: [`${dsuDir}/deployments/goerli`],
    optimismGoerli: [`${dsuDir}/deployments/optimismGoerli`],
    arbitrumGoerli: [`${dsuDir}/deployments/arbitrumGoerli`],
    arbitrum: [`${dsuDir}/deployments/arbitrum`],
    optimism: [`${dsuDir}/deployments/optimism`],
    mainnet: [`${dsuDir}/deployments/mainnet`],
    hardhat: [`${dsuDir}/deployments/mainnet`],
    localhost: [`${dsuDir}/deployments/localhost`],
  },
})

export default config
