# 一灯教育智能合约项目

这是一个基于以太坊的教育平台智能合约项目，包含以下合约：

- `YiDengToken`: ERC20 代币合约，用于平台内部支付
- `CourseCertificate`: ERC721 NFT 合约，用于发放课程完成证书
- `CourseMarket`: 课程市场合约，处理课程购买和完成验证
- `CourseRegistry`: 教师注册和课程注册管理合约
- `CourseReward`: 课程奖励合约，用于发放完成课程的奖励

## 安装依赖

```bash
pnpm install
```

## 配置环境变量

复制 `.env.example` 文件为 `.env`，并填写以下信息：

```
PRIVATE_KEY=your_private_key_here
SEPOLIA_RPC_URL=your_sepolia_rpc_url_here
ETHERSCAN_API_KEY=your_etherscan_api_key_here
```

## 编译合约

```bash
npx hardhat compile
```

## 部署合约

本地部署：
```bash
npx hardhat run scripts/deploy.ts --network localhost
```

Sepolia 测试网部署：
```bash
npx hardhat run scripts/deploy.ts --network sepolia
```

## 验证合约

```bash
npx hardhat verify --network sepolia <CONTRACT_ADDRESS>
```

## 测试

```bash
npx hardhat test
```
