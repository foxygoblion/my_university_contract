import { ethers } from "hardhat";

async function main() {
  // 部署 YiDengToken
  const YiDengToken = await ethers.getContractFactory("YiDengToken");
  const token = await YiDengToken.deploy();
  await token.waitForDeployment();
  console.log("YiDengToken deployed to:", await token.getAddress());

  // 部署 CourseCertificate
  const CourseCertificate = await ethers.getContractFactory("CourseCertificate");
  const certificate = await CourseCertificate.deploy();
  await certificate.waitForDeployment();
  console.log("CourseCertificate deployed to:", await certificate.getAddress());

  // 部署 CourseMarket
  const CourseMarket = await ethers.getContractFactory("CourseMarket");
  const market = await CourseMarket.deploy(
    await token.getAddress(),
    await certificate.getAddress()
  );
  await market.waitForDeployment();
  console.log("CourseMarket deployed to:", await market.getAddress());

  // 部署 CourseRegistry
  const CourseRegistry = await ethers.getContractFactory("CourseRegistry");
  const registry = await CourseRegistry.deploy(await market.getAddress());
  await registry.waitForDeployment();
  console.log("CourseRegistry deployed to:", await registry.getAddress());

  // 部署 CourseReward
  const CourseReward = await ethers.getContractFactory("CourseReward");
  const reward = await CourseReward.deploy(
    await token.getAddress(),
    await certificate.getAddress()
  );
  await reward.waitForDeployment();
  console.log("CourseReward deployed to:", await reward.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}); 