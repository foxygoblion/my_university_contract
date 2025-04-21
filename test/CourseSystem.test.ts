import { expect } from "chai";
import { ethers } from "hardhat";
import { 
  YiDengToken,
  CourseMarket,
  CourseRegistry,
  CourseCertificate,
  CourseReward
} from "../typechain-types";

describe("Course System", function () {
  let yiDengToken: YiDengToken;
  let courseMarket: CourseMarket;
  let courseRegistry: CourseRegistry;
  let courseCertificate: CourseCertificate;
  let courseReward: CourseReward;
  let owner: any;
  let teacher: any;
  let student: any;

  const COURSE_ID = "COURSE_001";
  const COURSE_NAME = "Web3 Development";
  const COURSE_PRICE = ethers.parseEther("100"); // 100 YD tokens

  beforeEach(async function () {
    // 获取测试账户
    [owner, teacher, student] = await ethers.getSigners();

    // 部署合约
    const YiDengToken = await ethers.getContractFactory("YiDengToken");
    yiDengToken = await YiDengToken.deploy();

    const CourseCertificate = await ethers.getContractFactory("CourseCertificate");
    courseCertificate = await CourseCertificate.deploy();

    const CourseMarket = await ethers.getContractFactory("CourseMarket");
    courseMarket = await CourseMarket.deploy(
      await yiDengToken.getAddress(),
      await courseCertificate.getAddress()
    );

    const CourseRegistry = await ethers.getContractFactory("CourseRegistry");
    courseRegistry = await CourseRegistry.deploy(await courseMarket.getAddress());

    const CourseReward = await ethers.getContractFactory("CourseReward");
    courseReward = await CourseReward.deploy(
      await yiDengToken.getAddress(),
      await courseCertificate.getAddress()
    );

    // 初始设置
    await courseRegistry.registerTeacher(teacher.address);
    await yiDengToken.mint(student.address, ethers.parseEther("1000")); // 给学生铸造1000个代币
  });

  describe("Course Creation and Purchase", function () {
    beforeEach(async function () {
      // 添加课程
      await courseMarket.addCourse(COURSE_ID, COURSE_NAME, COURSE_PRICE);
    });

    it("Should allow student to purchase course", async function () {
      // 学生授权代币给市场合约
      await yiDengToken.connect(student).approve(
        await courseMarket.getAddress(),
        COURSE_PRICE
      );

      // 购买课程
      await courseMarket.connect(student).purchaseCourse(COURSE_ID);

      // 验证购买状态
      expect(await courseMarket.hasCourse(student.address, COURSE_ID)).to.be.true;
    });

    it("Should allow course completion and certificate minting", async function () {
      // 学生购买课程
      await yiDengToken.connect(student).approve(
        await courseMarket.getAddress(),
        COURSE_PRICE
      );
      await courseMarket.connect(student).purchaseCourse(COURSE_ID);

      // 验证课程完成并铸造证书
      await courseMarket.verifyCourseCompletion(student.address, COURSE_ID);

      // 验证证书是否已铸造
      expect(await courseCertificate.hasCertificate(student.address, COURSE_ID)).to.be.true;
    });
  });

  describe("Course Rewards", function () {
    it("Should allow setting and claiming rewards", async function () {
      const rewardAmount = ethers.parseEther("50");
      const deadline = Math.floor(Date.now() / 1000) + 3600; // 1小时后

      // 设置课程奖励
      await courseReward.connect(teacher).setCourseReward(COURSE_ID, rewardAmount, deadline);

      // 铸造证书（模拟课程完成）
      await courseCertificate.grantRole(
        await courseCertificate.MINTER_ROLE(),
        owner.address
      );
      await courseCertificate.mintCertificate(
        student.address,
        COURSE_ID,
        "https://example.com/certificate"
      );

      // 给奖励合约转入代币
      await yiDengToken.transfer(
        await courseReward.getAddress(),
        rewardAmount
      );

      // 学生领取奖励
      await courseReward.connect(student).claimReward(COURSE_ID);

      // 验证奖励是否已领取
      const rewardInfo = await courseReward.getRewardInfo(COURSE_ID, student.address);
      expect(rewardInfo.claimed).to.be.true;
    });
  });
}); 