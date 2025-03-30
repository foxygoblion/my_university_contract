import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("DeployModule", (m) => {
  // 这里可以添加你的合约部署逻辑
  // 例如：
  // const myContract = m.contract("MyContract");
  
  return {
    // 返回部署的合约
    // myContract,
  };
}); 