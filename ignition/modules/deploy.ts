import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("UniversityModule", (m) => {
  // 部署 YiDengToken
  const yiDengToken = m.contract("YiDengToken");

  // 部署 CourseCertificate (不需要参数)
  const courseCertificate = m.contract("CourseCertificate");

  // 部署 CourseMarket (需要 YiDengToken 和 CourseCertificate 地址)
  const courseMarket = m.contract("CourseMarket", [yiDengToken, courseCertificate]);

  // 部署 CourseRegistry (需要 CourseMarket 地址)
  const courseRegistry = m.contract("CourseRegistry", [courseMarket]);

  // 部署 CourseReward (需要 YiDengToken 和 CourseCertificate 地址)
  const courseReward = m.contract("CourseReward", [yiDengToken, courseCertificate]);

  return {
    yiDengToken,
    courseCertificate,
    courseMarket,
    courseRegistry,
    courseReward,
  };
}); 